-- Define the list of playlist names and URLs
set playlists to {{"GameMovie", "https://open.spotify.com/playlist/2DkBJllGx9wnoaeTHOOkBg?si=8bae67cee24e4df6"}, ¬
                  {"Clara's Theme", "https://open.spotify.com/playlist/3jxP4xSFxbhotY0CfiKT5i?si=62fa67e8ac2a4461"}, ¬
                  {"Mijn Favorieten", "https://open.spotify.com/playlist/7lCKea0llFbxtKXwlkZGfZ?si=e8a34960e6ef4d36"}, ¬
                  {"Genshin", "https://open.spotify.com/playlist/7dN43dWC40LgT2BSQYrsao?si=d4d449f29a1d4180"}, ¬
                  {"Rustig", "https://open.spotify.com/playlist/6CJsx8tp45bXrVb9z12Tf7?si=4492e8e5ee904d4e"}, ¬
                  {"Vrolijk", "https://open.spotify.com/playlist/3tbAAn2EAHqvFWWUaMf6CD?si=6f06e57ab1454a6f"}, ¬
                  {"Floris kookt", "https://open.spotify.com/playlist/3WeDkp3PxyvphS8iBwV1eE?si=3fe6d1a58a254ebf"}, ¬
                  {"Oldies", "https://open.spotify.com/playlist/497XfEy3DKUtwUXA2LAx17?si=d55c110b1fb740e2"}, ¬
                  {"De Fransen", "https://open.spotify.com/playlist/7D1R6kjK1rsPBGZ9s6GYzo?si=2718a42e128e4ea1"}}

-- Choose a random playlist
set randomIndex to (random number from 1 to (count of playlists))
set selectedPlaylist to item randomIndex of playlists
set playlistName to item 1 of selectedPlaylist
set playlistURL to item 2 of selectedPlaylist

-- Display the selected playlist name
display notification "Playing playlist: " & playlistName with title "Spotify Playlist"

-- Open the selected playlist in the default web browser
tell application "Spotify"
    activate
    set shuffling to true
end tell

open location playlistURL