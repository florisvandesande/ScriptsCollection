#!/usr/bin/env python3
"""Sync Spotify playlists from one account into another account's library.

This script uses Spotify's OAuth PKCE flow so both accounts can sign in through
their own browser session. The source account can be opened in Safari and the
destination account in Google Chrome.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import http.server
import json
import secrets
import socketserver
import threading
import time
import urllib.parse
import subprocess
import webbrowser
from dataclasses import dataclass
from typing import Any

import requests

API = "https://api.spotify.com/v1"
AUTHORIZE_URL = "https://accounts.spotify.com/authorize"
TOKEN_URL = "https://accounts.spotify.com/api/token"
DEFAULT_REDIRECT_HOST = "127.0.0.1"
DEFAULT_REDIRECT_PORT = 8765
DEFAULT_REDIRECT_PATH = "/spotify/callback"
DEFAULT_SCOPES = (
    "playlist-read-private "
    "playlist-read-collaborative "
    "playlist-modify-private "
    "playlist-modify-public "
    "user-library-read "
    "user-library-modify "
    "user-follow-read "
    "user-follow-modify "
    "user-read-private"
)
BROWSER_COMMANDS = {
    "default": None,
    "safari": ["open", "-a", "Safari"],
    "chrome": ["open", "-a", "Google Chrome"],
}


def get_all_playlists(access_token: str) -> list[dict[str, Any]]:
    playlists: list[dict[str, Any]] = []
    url = f"{API}/me/playlists?limit=50"

    while url:
        response = requests.get(
            url,
            headers={"Authorization": f"Bearer {access_token}"},
            timeout=30,
        )
        response.raise_for_status()
        data = response.json()

        playlists.extend(data["items"])
        url = data.get("next")

    return playlists


def check_saved_playlists(
    destination_token: str,
    playlist_uris: list[str],
) -> dict[str, bool]:
    saved: dict[str, bool] = {}

    for index in range(0, len(playlist_uris), 40):
        batch = playlist_uris[index:index + 40]
        response = requests.get(
            f"{API}/me/library/contains",
            headers={"Authorization": f"Bearer {destination_token}"},
            params={"uris": ",".join(batch)},
            timeout=30,
        )
        response.raise_for_status()

        for uri, is_saved in zip(batch, response.json()):
            saved[uri] = is_saved

    return saved


def save_playlists(destination_token: str, playlist_uris: list[str]) -> None:
    for index in range(0, len(playlist_uris), 40):
        batch = playlist_uris[index:index + 40]
        response = requests.put(
            f"{API}/me/library",
            headers={"Authorization": f"Bearer {destination_token}"},
            params={"uris": ",".join(batch)},
            timeout=30,
        )
        if response.ok:
            continue

        if _is_insufficient_scope_response(response):
            save_playlists_via_follow_endpoint(destination_token, batch)
            continue

        response.raise_for_status()


def save_playlists_via_follow_endpoint(
    destination_token: str,
    playlist_uris: list[str],
) -> None:
    for playlist_uri in playlist_uris:
        playlist_id = extract_playlist_id(playlist_uri)
        response = requests.put(
            f"{API}/playlists/{playlist_id}/followers",
            headers={"Authorization": f"Bearer {destination_token}"},
            json={"public": False},
            timeout=30,
        )
        response.raise_for_status()


def extract_playlist_id(playlist_uri: str) -> str:
    prefix = "spotify:playlist:"
    if not playlist_uri.startswith(prefix):
        raise ValueError(f"Unsupported playlist URI: {playlist_uri}")

    return playlist_uri[len(prefix):]


def _is_insufficient_scope_response(response: requests.Response) -> bool:
    if response.status_code != 403:
        return False

    try:
        payload = response.json()
    except ValueError:
        return False

    error = payload.get("error")
    if isinstance(error, dict):
        message = error.get("message", "")
    else:
        message = str(error)

    return "insufficient client scope" in message.lower()


def sync_source_playlists_to_destination(
    source_token: str,
    destination_token: str,
    source_user_id: str,
) -> dict[str, int]:
    print("Fetching playlists from the source account...")
    playlists = get_all_playlists(source_token)

    source_owned_uris = [
        playlist["uri"]
        for playlist in playlists
        if playlist["owner"]["id"] == source_user_id
    ]
    print(
        f"Found {len(playlists)} accessible playlists, "
        f"{len(source_owned_uris)} owned by the source account."
    )

    print("Checking which source playlists are already saved in the destination library...")
    saved_map = check_saved_playlists(destination_token, source_owned_uris)

    missing_uris = [
        uri
        for uri in source_owned_uris
        if not saved_map.get(uri, False)
    ]
    print(f"{len(missing_uris)} playlists still need to be added.")

    if missing_uris:
        print("Saving missing playlists to the destination library...")
        save_playlists(destination_token, missing_uris)

    return {
        "found": len(source_owned_uris),
        "added": len(missing_uris),
    }


def get_current_user_profile(access_token: str) -> dict[str, Any]:
    response = requests.get(
        f"{API}/me",
        headers={"Authorization": f"Bearer {access_token}"},
        timeout=30,
    )
    response.raise_for_status()

    return response.json()


def try_get_current_user_profile(access_token: str) -> dict[str, Any] | None:
    try:
        return get_current_user_profile(access_token)
    except requests.HTTPError as error:
        response = error.response
        if response is not None and response.status_code == 403:
            return None
        raise


@dataclass
class OAuthSession:
    access_token: str
    refresh_token: str | None
    expires_in: int
    scope: str
    user_id: str
    display_name: str | None


@dataclass
class OAuthCallbackResult:
    code: str | None = None
    state: str | None = None
    error: str | None = None


class OAuthCallbackHandler(http.server.BaseHTTPRequestHandler):
    result: OAuthCallbackResult | None = None
    callback_path = DEFAULT_REDIRECT_PATH
    ready_event: threading.Event | None = None

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != self.callback_path:
            self.send_error(404, "Not Found")
            return

        query = urllib.parse.parse_qs(parsed.query)
        self.__class__.result = OAuthCallbackResult(
            code=_first_query_value(query, "code"),
            state=_first_query_value(query, "state"),
            error=_first_query_value(query, "error"),
        )

        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(
            (
                "<!doctype html><html><body>"
                "<h1>Spotify login received</h1>"
                "<p>You can return to Terminal.</p>"
                "</body></html>"
            ).encode("utf-8")
        )

        if self.ready_event is not None:
            self.ready_event.set()

    def log_message(self, format: str, *args: Any) -> None:
        return


def _first_query_value(query: dict[str, list[str]], key: str) -> str | None:
    values = query.get(key)
    if not values:
        return None

    return values[0]


def build_code_verifier() -> str:
    verifier_bytes = secrets.token_bytes(64)
    return base64.urlsafe_b64encode(verifier_bytes).decode("ascii").rstrip("=")


def build_code_challenge(code_verifier: str) -> str:
    digest = hashlib.sha256(code_verifier.encode("ascii")).digest()
    return base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")


def build_redirect_uri(host: str, port: int, path: str) -> str:
    return f"http://{host}:{port}{path}"


def start_callback_server(
    host: str,
    port: int,
    path: str,
) -> tuple[socketserver.TCPServer, threading.Event, threading.Thread]:
    ready_event = threading.Event()

    class CallbackServer(socketserver.TCPServer):
        allow_reuse_address = True

    OAuthCallbackHandler.result = None
    OAuthCallbackHandler.callback_path = path
    OAuthCallbackHandler.ready_event = ready_event

    server = CallbackServer((host, port), OAuthCallbackHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    return server, ready_event, thread


def request_oauth_session(
    client_id: str,
    redirect_uri: str,
    scopes: str,
    browser_name: str,
    label: str,
    timeout_seconds: int,
    require_profile: bool,
) -> OAuthSession:
    code_verifier = build_code_verifier()
    state = secrets.token_urlsafe(24)
    code_challenge = build_code_challenge(code_verifier)
    authorize_params = {
        "client_id": client_id,
        "response_type": "code",
        "redirect_uri": redirect_uri,
        "scope": scopes,
        "code_challenge_method": "S256",
        "code_challenge": code_challenge,
        "state": state,
        "show_dialog": "true",
    }
    authorize_url = (
        f"{AUTHORIZE_URL}?{urllib.parse.urlencode(authorize_params)}"
    )

    print(
        f"Opening Spotify login for the {label} account in "
        f"{browser_name.title()}..."
    )
    open_url_in_browser(authorize_url, browser_name)

    callback_result = wait_for_callback(timeout_seconds)
    if callback_result.error:
        raise RuntimeError(
            f"Spotify returned an authorization error for the {label} account: "
            f"{callback_result.error}"
        )

    if callback_result.state != state:
        raise RuntimeError(
            f"The returned OAuth state did not match for the {label} account."
        )

    if not callback_result.code:
        raise RuntimeError(
            f"No authorization code was returned for the {label} account."
        )

    token_response = requests.post(
        TOKEN_URL,
        data={
            "client_id": client_id,
            "grant_type": "authorization_code",
            "code": callback_result.code,
            "redirect_uri": redirect_uri,
            "code_verifier": code_verifier,
        },
        timeout=30,
    )
    token_response.raise_for_status()
    token_payload = token_response.json()

    access_token = token_payload["access_token"]
    if require_profile:
        user_profile = get_current_user_profile(access_token)
    else:
        user_profile = try_get_current_user_profile(access_token)

    user_id = ""
    display_name: str | None = None
    if user_profile is not None:
        user_id = user_profile["id"]
        display_name = user_profile.get("display_name")

    return OAuthSession(
        access_token=access_token,
        refresh_token=token_payload.get("refresh_token"),
        expires_in=token_payload["expires_in"],
        scope=token_payload.get("scope", ""),
        user_id=user_id,
        display_name=display_name,
    )


def wait_for_callback(timeout_seconds: int) -> OAuthCallbackResult:
    start_time = time.time()
    while time.time() - start_time < timeout_seconds:
        ready_event = OAuthCallbackHandler.ready_event
        if ready_event is not None and ready_event.wait(timeout=0.25):
            if OAuthCallbackHandler.result is None:
                break
            return OAuthCallbackHandler.result

    raise TimeoutError(
        "Timed out while waiting for the Spotify login to return to the local "
        "callback URL."
    )


def open_url_in_browser(url: str, browser_name: str) -> None:
    browser_key = browser_name.lower()
    command_prefix = BROWSER_COMMANDS.get(browser_key)

    if browser_key not in BROWSER_COMMANDS:
        raise ValueError(
            f"Unsupported browser '{browser_name}'. Use safari, chrome, or default."
        )

    if command_prefix is None:
        if not webbrowser.open(url):
            raise RuntimeError(
                "Could not open the default browser automatically."
            )
        return
    subprocess.run(
        [*command_prefix, url],
        check=True,
    )


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Sign in to two Spotify accounts and save the source account's own "
            "playlists into the destination account's library."
        )
    )
    parser.add_argument(
        "--client-id",
        required=True,
        help=(
            "Spotify application client ID. Create an app in the Spotify "
            "developer dashboard and allow the redirect URI used below."
        ),
    )
    parser.add_argument(
        "--redirect-host",
        default=DEFAULT_REDIRECT_HOST,
        help=f"Local callback host. Default: {DEFAULT_REDIRECT_HOST}",
    )
    parser.add_argument(
        "--redirect-port",
        type=int,
        default=DEFAULT_REDIRECT_PORT,
        help=f"Local callback port. Default: {DEFAULT_REDIRECT_PORT}",
    )
    parser.add_argument(
        "--redirect-path",
        default=DEFAULT_REDIRECT_PATH,
        help=f"Local callback path. Default: {DEFAULT_REDIRECT_PATH}",
    )
    parser.add_argument(
        "--source-browser",
        choices=sorted(BROWSER_COMMANDS.keys()),
        default="safari",
        help="Browser for the source Spotify account login. Default: safari",
    )
    parser.add_argument(
        "--destination-browser",
        choices=sorted(BROWSER_COMMANDS.keys()),
        default="chrome",
        help=(
            "Browser for the destination Spotify account login. "
            "Default: chrome"
        ),
    )
    parser.add_argument(
        "--scopes",
        default=DEFAULT_SCOPES,
        help=(
            "Spotify OAuth scopes. Default covers reading playlists and "
            "saving them to the destination library."
        ),
    )
    parser.add_argument(
        "--timeout-seconds",
        type=int,
        default=180,
        help="Seconds to wait for each browser login callback. Default: 180",
    )
    parser.add_argument(
        "--print-tokens",
        action="store_true",
        help=(
            "Print the access and refresh tokens after login. Use this only "
            "if you explicitly need to inspect or reuse them."
        ),
    )
    return parser.parse_args()


def print_login_summary(label: str, session: OAuthSession) -> None:
    display_name = session.display_name or "(no display name)"
    if session.user_id:
        print(
            f"{label.title()} account: {display_name} "
            f"[user id: {session.user_id}]"
        )
    else:
        print(
            f"{label.title()} account login completed, but Spotify did not return "
            "profile details for this token."
        )

    print(f"{label.title()} granted scopes: {session.scope}")


def print_token_summary(label: str, session: OAuthSession) -> None:
    token_details = {
        "access_token": session.access_token,
        "refresh_token": session.refresh_token,
        "expires_in": session.expires_in,
        "scope": session.scope,
        "user_id": session.user_id,
        "display_name": session.display_name,
    }
    print(f"{label.title()} token details:")
    print(json.dumps(token_details, indent=2))


def main() -> int:
    args = parse_arguments()
    redirect_uri = build_redirect_uri(
        args.redirect_host,
        args.redirect_port,
        args.redirect_path,
    )

    print("Before continuing, add this redirect URI to your Spotify app:")
    print(redirect_uri)

    server, _, thread = start_callback_server(
        args.redirect_host,
        args.redirect_port,
        args.redirect_path,
    )

    try:
        source_session = request_oauth_session(
            client_id=args.client_id,
            redirect_uri=redirect_uri,
            scopes=args.scopes,
            browser_name=args.source_browser,
            label="source",
            timeout_seconds=args.timeout_seconds,
            require_profile=True,
        )
        print_login_summary("source", source_session)

        OAuthCallbackHandler.result = None
        if OAuthCallbackHandler.ready_event is not None:
            OAuthCallbackHandler.ready_event.clear()

        destination_session = request_oauth_session(
            client_id=args.client_id,
            redirect_uri=redirect_uri,
            scopes=args.scopes,
            browser_name=args.destination_browser,
            label="destination",
            timeout_seconds=args.timeout_seconds,
            require_profile=False,
        )
        print_login_summary("destination", destination_session)

        if args.print_tokens:
            print_token_summary("source", source_session)
            print_token_summary("destination", destination_session)

        try:
            sync_result = sync_source_playlists_to_destination(
                source_token=source_session.access_token,
                destination_token=destination_session.access_token,
                source_user_id=source_session.user_id,
            )
        except requests.HTTPError as error:
            response = error.response
            if response is None:
                raise

            print("Spotify API request failed during sync.")
            print(f"Status: {response.status_code}")
            try:
                print(json.dumps(response.json(), indent=2))
            except ValueError:
                print(response.text)
            return 1

        print("Sync completed.")
        print(json.dumps(sync_result, indent=2))
        return 0
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=1)


if __name__ == "__main__":
    raise SystemExit(main())
