#!/usr/bin/env swift

import AppKit
import CoreText
import Foundation
import SceneKit

struct CLIOptions {
    let input_source: InputSource
    let output_directory: URL
    let export_format: ExportFormat
    let color_export_options: ColorExportOptions
}

enum InputSource {
    case single(String)
    case batch(URL)
}

enum ExportFormat {
    case stl
    case three_mf
    case obj
    case all

    static func parse(_ value: String) -> ExportFormat? {
        switch value.lowercased(with: Locale(identifier: "en_US_POSIX")) {
        case "stl":
            return .stl
        case "3mf":
            return .three_mf
        case "obj":
            return .obj
        case "all":
            return .all
        default:
            return nil
        }
    }

    var cli_value: String {
        switch self {
        case .stl:
            return "stl"
        case .three_mf:
            return "3mf"
        case .obj:
            return "obj"
        case .all:
            return "all"
        }
    }

    var includes_stl: Bool {
        self == .stl || self == .all
    }

    var includes_three_mf: Bool {
        self == .three_mf || self == .all
    }

    var includes_obj: Bool {
        self == .obj || self == .all
    }

    var includes_color_capable_export: Bool {
        includes_three_mf || includes_obj
    }
}

struct LabelReference {
    let kind: LabelKind
    let outer_loop: [CGPoint]
    let inner_loop: [CGPoint]
    let bounds: CGRect
    let text_bounds: CGRect
}

struct Triangle3D {
    let a: SIMD3<Double>
    let b: SIMD3<Double>
    let c: SIMD3<Double>

    func translated(x: Double = 0, y: Double = 0, z: Double = 0) -> Triangle3D {
        Triangle3D(
            a: SIMD3<Double>(a.x + x, a.y + y, a.z + z),
            b: SIMD3<Double>(b.x + x, b.y + y, b.z + z),
            c: SIMD3<Double>(c.x + x, c.y + y, c.z + z)
        )
    }

    func normal() -> SIMD3<Double> {
        let u = b - a
        let v = c - a
        let cross = SIMD3<Double>(
            u.y * v.z - u.z * v.y,
            u.z * v.x - u.x * v.z,
            u.x * v.y - u.y * v.x
        )
        let length = sqrt(cross.x * cross.x + cross.y * cross.y + cross.z * cross.z)
        guard length > 0 else {
            return SIMD3<Double>(0, 0, 0)
        }
        return cross / length
    }

    func centroid_xy() -> CGPoint {
        CGPoint(x: (a.x + b.x + c.x) / 3.0, y: (a.y + b.y + c.y) / 3.0)
    }

    func is_horizontal(at z_value: Double, epsilon: Double = 0.0001) -> Bool {
        abs(a.z - z_value) <= epsilon &&
            abs(b.z - z_value) <= epsilon &&
            abs(c.z - z_value) <= epsilon
    }
}

struct MeshTriangle {
    let v1: Int
    let v2: Int
    let v3: Int
}

struct Mesh3D {
    let vertices: [SIMD3<Double>]
    let triangles: [MeshTriangle]
}

enum ExportColor: Int, CaseIterable {
    case white = 0
    case black = 1

    var three_mf_hex: String {
        switch self {
        case .white:
            return "#FFFFFFFF"
        case .black:
            return "#000000FF"
        }
    }

    var obj_components: SIMD3<Double> {
        switch self {
        case .white:
            return SIMD3<Double>(1, 1, 1)
        case .black:
            return SIMD3<Double>(0, 0, 0)
        }
    }
}

struct ThreeMFMeshObject {
    let object_id: Int
    let mesh: Mesh3D
    let color: ExportColor?
}

struct ThreeMFColorGroup {
    let resource_id: Int
    let colors: [ExportColor]
}

struct ThreeMFDocument {
    let color_group: ThreeMFColorGroup?
    let mesh_objects: [ThreeMFMeshObject]
    let build_object_id: Int
}

struct TextLayout {
    let lines: [String]
    let path: NSBezierPath
    let effective_font_size: CGFloat
}

struct ColorExportOptions {
    let color_letters: Bool
    let color_border: Bool

    var has_color_parts: Bool {
        color_letters || color_border
    }
}

struct PlantExportResult {
    let plant_name: String
    let slug: String
    let output_paths: [URL]
}

struct LabelExportGeometry {
    let stl_triangles: [Triangle3D]
    let color_parts: [ExportPart]
    let obj_geometry: OBJExportGeometry
}

struct ExportPart {
    let role: String
    let triangles: [Triangle3D]
    let color: ExportColor?
}

struct OBJExportGeometry {
    let triangles: [Triangle3D]
    let black_vertex_keys: Set<QuantizedVertex>

    var includes_colors: Bool {
        !black_vertex_keys.isEmpty
    }
}

struct BatchInputEntry {
    let line_number: Int
    let plant_name: String
}

struct ResolvedBatchInputEntry {
    let line_number: Int
    let plant_name: String
    let slug: String
}

struct BatchExportFailure {
    let line_number: Int
    let plant_name: String
    let message: String
}

struct QuantizedPoint: Hashable, Comparable {
    let x: Int
    let y: Int

    static func < (lhs: QuantizedPoint, rhs: QuantizedPoint) -> Bool {
        if lhs.x != rhs.x {
            return lhs.x < rhs.x
        }

        return lhs.y < rhs.y
    }
}

struct EdgeKey: Hashable {
    let start: QuantizedPoint
    let end: QuantizedPoint

    init(_ first: QuantizedPoint, _ second: QuantizedPoint) {
        if first <= second {
            start = first
            end = second
        } else {
            start = second
            end = first
        }
    }
}

struct QuantizedVertex: Hashable {
    let x: Int64
    let y: Int64
    let z: Int64
}

enum LabelKind: CaseIterable {
    case rounded_corners
    case with_stick
    case inverted_rounded_corners

    var reference_file_name: String {
        switch self {
        case .rounded_corners:
            return "plantlabel_rounded_corners.stl"
        case .with_stick:
            return "plantlabel_with_stick.stl"
        case .inverted_rounded_corners:
            return "plantlabel_inverted_rounded_corners.stl"
        }
    }

    var output_suffix: String {
        switch self {
        case .rounded_corners:
            return "rounded-corners"
        case .with_stick:
            return "with-stick"
        case .inverted_rounded_corners:
            return "inverted-rounded-corners"
        }
    }

    var base_height: Double {
        switch self {
        case .rounded_corners, .inverted_rounded_corners:
            return 2.0
        case .with_stick:
            return 1.0
        }
    }

    var top_height: Double {
        switch self {
        case .rounded_corners, .inverted_rounded_corners:
            return 3.0
        case .with_stick:
            return 2.0
        }
    }

    var display_name: String {
        switch self {
        case .rounded_corners:
            return "rounded corners"
        case .with_stick:
            return "with stick"
        case .inverted_rounded_corners:
            return "inverted rounded corners"
        }
    }
}

enum ScriptError: LocalizedError {
    case missing_argument(String)
    case invalid_argument(String)
    case missing_font(URL)
    case unsupported_characters(String)
    case input_file_unreadable(URL, String)
    case empty_batch_input(URL)
    case reference_file_missing(URL)
    case reference_shape_unusable(URL)
    case export_failed(String)
    case name_too_long(String)
    case invalid_format(String)

    var errorDescription: String? {
        switch self {
        case let .missing_argument(message),
             let .invalid_argument(message),
             let .export_failed(message),
             let .name_too_long(message),
             let .invalid_format(message):
            return message
        case let .missing_font(url):
            return "The Merriweather Bold Italic font could not be loaded from \(url.path). Check that the font is installed before running the script."
        case let .unsupported_characters(value):
            return "The name contains characters that Merriweather Bold Italic cannot render: \(value)"
        case let .input_file_unreadable(url, reason):
            return "Could not read the batch input file at \(url.path). \(reason)"
        case let .empty_batch_input(url):
            return "The batch input file at \(url.path) did not contain any usable plant names. Add one plant name per line, and optional comments can start with #."
        case let .reference_file_missing(url):
            return "The reference STL file is missing: \(url.path)"
        case let .reference_shape_unusable(url):
            return "The reference STL file could not be converted into a usable label shape: \(url.path)"
        }
    }
}

let minimum_font_size: CGFloat = 5.0
let layout_font_size: CGFloat = 100.0
let line_gap_ratio: CGFloat = 0.08
let geometry_flatness: CGFloat = 0.02
let color_cap_thickness: Double = 0.2

func main() throws -> Int {
    let script_url = resolved_script_url()
    let script_directory = script_url.deletingLastPathComponent()
    let options = try parse_cli_options()
    let font = try load_reference_font()
    let references = try load_references(script_directory: script_directory)
    try FileManager.default.createDirectory(at: options.output_directory, withIntermediateDirectories: true)

    switch options.input_source {
    case let .single(plant_name):
        let result = try export_plant_labels(
            plant_name: plant_name,
            slug: slugify(plant_name),
            output_directory: options.output_directory,
            export_format: options.export_format,
            color_export_options: options.color_export_options,
            references: references,
            font: font
        )

        print("Plant label export complete.")
        print("Plant name: \(result.plant_name)")
        print("Slug: \(result.slug)")
        print("Format: \(options.export_format.cli_value)")
        for output_path in result.output_paths {
            print(output_path.path)
        }
        return 0

    case let .batch(input_file_url):
        let entries = try load_batch_input_entries(from: input_file_url)
        let resolved_entries = resolve_batch_slugs(for: entries)
        var success_count = 0
        var failures: [BatchExportFailure] = []

        for entry in resolved_entries {
            do {
                let result = try export_plant_labels(
                    plant_name: entry.plant_name,
                    slug: entry.slug,
                    output_directory: options.output_directory,
                    export_format: options.export_format,
                    color_export_options: options.color_export_options,
                    references: references,
                    font: font
                )

                success_count += 1
                print("[OK] line \(entry.line_number) | \(result.plant_name) | slug: \(result.slug)")
                for output_path in result.output_paths {
                    print(output_path.path)
                }
            } catch {
                failures.append(
                    BatchExportFailure(
                        line_number: entry.line_number,
                        plant_name: entry.plant_name,
                        message: error_message(for: error)
                    )
                )
            }
        }

        print("Batch plant label export complete.")
        print("Input file: \(input_file_url.path)")
        print("Format: \(options.export_format.cli_value)")
        print("Usable plant names: \(resolved_entries.count)")
        print("Succeeded: \(success_count)")
        print("Failed: \(failures.count)")

        if !failures.isEmpty {
            for failure in failures {
                fputs("[FAILED] line \(failure.line_number) | \(failure.plant_name) | \(failure.message)\n", stderr)
            }
        }

        return failures.isEmpty ? 0 : 1
    }
}

func resolved_script_url() -> URL {
    let current_directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return URL(fileURLWithPath: CommandLine.arguments[0], relativeTo: current_directory).standardizedFileURL
}

func parse_cli_options() throws -> CLIOptions {
    let default_output_directory = resolved_script_url()
        .deletingLastPathComponent()
        .appendingPathComponent("output", isDirectory: true)
    var index = 1
    var plant_name: String?
    var input_file_url: URL?
    var output_directory = default_output_directory
    var export_format = ExportFormat.stl
    var color_letters = false
    var color_border = false

    while index < CommandLine.arguments.count {
        let argument = CommandLine.arguments[index]
        switch argument {
        case "--name":
            index += 1
            guard index < CommandLine.arguments.count else {
                throw ScriptError.missing_argument("Missing a value after --name. Example: swift generate_plant_labels.swift --name \"Agastache rugosa 'Black Adder'\"")
            }
            plant_name = normalize_name(CommandLine.arguments[index])
        case "--input-file":
            index += 1
            guard index < CommandLine.arguments.count else {
                throw ScriptError.missing_argument("Missing a value after --input-file. Example: swift generate_plant_labels.swift --input-file plant-names.txt")
            }
            input_file_url = URL(
                fileURLWithPath: CommandLine.arguments[index],
                relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            ).standardizedFileURL
        case "--output-dir":
            index += 1
            guard index < CommandLine.arguments.count else {
                throw ScriptError.missing_argument("Missing a value after --output-dir. Example: --output-dir output")
            }
            output_directory = URL(fileURLWithPath: CommandLine.arguments[index], relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
        case "--format":
            index += 1
            guard index < CommandLine.arguments.count else {
                throw ScriptError.missing_argument("Missing a value after --format. Use stl, 3mf, obj, or all.")
            }
            let format_value = CommandLine.arguments[index]
            if format_value.lowercased(with: Locale(identifier: "en_US_POSIX")) == "both" {
                throw ScriptError.invalid_format("The --format value 'both' is no longer supported. Use --format all instead.")
            }
            guard let parsed_format = ExportFormat.parse(format_value) else {
                throw ScriptError.invalid_format("Unsupported --format value: \(format_value). Use stl, 3mf, obj, or all.")
            }
            export_format = parsed_format
        case "--color-letters":
            color_letters = true
        case "--color-border":
            color_border = true
        case "--help", "-h":
            print_usage()
            Foundation.exit(0)
        default:
            throw ScriptError.invalid_argument("Unknown argument: \(argument)\n\nUse --help to see the supported options.")
        }
        index += 1
    }

    if plant_name != nil, input_file_url != nil {
        throw ScriptError.invalid_argument("Use either --name or --input-file, not both. Example: swift generate_plant_labels.swift --input-file plant-names.txt")
    }

    let color_export_options = ColorExportOptions(color_letters: color_letters, color_border: color_border)
    if color_export_options.has_color_parts, !export_format.includes_color_capable_export {
        throw ScriptError.invalid_argument("The --color-letters and --color-border options only work when --format includes 3mf or obj. Use --format 3mf, --format obj, or --format all.")
    }

    let input_source: InputSource
    if let plant_name, !plant_name.isEmpty {
        input_source = .single(plant_name)
    } else if let input_file_url {
        input_source = .batch(input_file_url)
    } else {
        throw ScriptError.missing_argument(
            "Missing input. Use --name \"Agastache rugosa 'Black Adder'\" for one plant or --input-file plant-names.txt for batch export."
        )
    }

    return CLIOptions(
        input_source: input_source,
        output_directory: output_directory,
        export_format: export_format,
        color_export_options: color_export_options
    )
}

func print_usage() {
    print(
        """
        Generate three plant labels from one Latin plant name or from a text file with multiple names.

        Usage:
          swift generate_plant_labels.swift --name "Agastache rugosa 'Black Adder'" [--format stl|3mf|obj|all] [--color-letters] [--color-border] [--output-dir output]
          swift generate_plant_labels.swift --input-file plant-names.txt [--format stl|3mf|obj|all] [--color-letters] [--color-border] [--output-dir output]

        Batch file format:
          One plant name per line.
          Blank lines are ignored.
          Lines starting with # are treated as comments.

        Reference STL files:
          The script reads the three reference STL files from example/ by default.

        Color-cap options for 3MF and OBJ:
          --color-letters  Make the top 0.2 mm of the raised letters black.
          --color-border   Make the top 0.2 mm of the raised border black.
        """
    )
}

func normalize_name(_ raw_value: String) -> String {
    raw_value
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func slugify(_ value: String) -> String {
    var folded = value.precomposedStringWithCompatibilityMapping
    if let latin = folded.applyingTransform(.toLatin, reverse: false)?
        .applyingTransform(.stripCombiningMarks, reverse: false)
    {
        folded = latin
    }
    folded = folded.lowercased(with: Locale(identifier: "en_US_POSIX"))

    let invalid_pattern = try! NSRegularExpression(pattern: "[^a-z0-9]+")
    let range = NSRange(location: 0, length: folded.utf16.count)
    var slug = invalid_pattern.stringByReplacingMatches(in: folded, options: [], range: range, withTemplate: "-")
    slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

    while slug.contains("--") {
        slug = slug.replacingOccurrences(of: "--", with: "-")
    }

    return slug.isEmpty ? "plant-label" : slug
}

func load_batch_input_entries(from url: URL) throws -> [BatchInputEntry] {
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        throw ScriptError.input_file_unreadable(url, error.localizedDescription)
    }

    guard let contents = String(data: data, encoding: .utf8) else {
        throw ScriptError.input_file_unreadable(url, "The file must be saved as UTF-8 plain text.")
    }

    var entries: [BatchInputEntry] = []
    let lines = contents.components(separatedBy: .newlines)
    for (index, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("#") {
            continue
        }

        let normalized = normalize_name(trimmed)
        if !normalized.isEmpty {
            entries.append(BatchInputEntry(line_number: index + 1, plant_name: normalized))
        }
    }

    guard !entries.isEmpty else {
        throw ScriptError.empty_batch_input(url)
    }

    return entries
}

func resolve_batch_slugs(for entries: [BatchInputEntry]) -> [ResolvedBatchInputEntry] {
    var counts: [String: Int] = [:]

    return entries.map { entry in
        let base_slug = slugify(entry.plant_name)
        let next_count = counts[base_slug, default: 0] + 1
        counts[base_slug] = next_count
        let resolved_slug = next_count == 1 ? base_slug : "\(base_slug)-\(next_count)"

        return ResolvedBatchInputEntry(
            line_number: entry.line_number,
            plant_name: entry.plant_name,
            slug: resolved_slug
        )
    }
}

func load_references(script_directory: URL) throws -> [LabelKind: LabelReference] {
    var references: [LabelKind: LabelReference] = [:]
    for kind in LabelKind.allCases {
        references[kind] = try load_reference(kind: kind, script_directory: script_directory)
    }
    return references
}

func export_plant_labels(
    plant_name: String,
    slug: String,
    output_directory: URL,
    export_format: ExportFormat,
    color_export_options: ColorExportOptions,
    references: [LabelKind: LabelReference],
    font: CTFont
) throws -> PlantExportResult {
    try ensure_supported_characters(in: plant_name, font: font)

    var output_paths: [URL] = []

    for kind in LabelKind.allCases {
        guard let reference = references[kind] else {
            throw ScriptError.export_failed("The cached reference shape for \(kind.display_name) is missing.")
        }

        let text_layout = try layout_text(
            plant_name: plant_name,
            target_bounds: reference.text_bounds,
            font: font
        )
        let geometry = try build_label_geometry(
            kind: kind,
            reference: reference,
            text_layout: text_layout,
            color_export_options: color_export_options
        )

        let base_output_url = output_directory.appendingPathComponent("\(slug)-\(kind.output_suffix)")

        if export_format.includes_stl {
            let stl_url = base_output_url.appendingPathExtension("stl")
            try write_binary_stl(triangles: geometry.stl_triangles, to: stl_url, header: "\(plant_name) - \(kind.display_name)")
            output_paths.append(stl_url)
        }

        if export_format.includes_three_mf {
            let three_mf_url = base_output_url.appendingPathExtension("3mf")
            try write_geometry_three_mf(parts: geometry.color_parts, to: three_mf_url)
            output_paths.append(three_mf_url)
        }

        if export_format.includes_obj {
            let obj_url = base_output_url.appendingPathExtension("obj")
            try write_obj(geometry: geometry.obj_geometry, to: obj_url)
            output_paths.append(obj_url)
        }
    }

    return PlantExportResult(plant_name: plant_name, slug: slug, output_paths: output_paths)
}

func build_label_geometry(
    kind: LabelKind,
    reference: LabelReference,
    text_layout: TextLayout,
    color_export_options: ColorExportOptions
) throws -> LabelExportGeometry {
    let outer_path = bezier_path(from: reference.outer_loop)
    let inner_path = bezier_path(from: reference.inner_loop)
    let border_path = ring_path(outer_path: outer_path, inner_path: inner_path)
    let fill_path = center_fill_path(inner_path: inner_path, text_path: text_layout.path)
    let raised_depth = kind.top_height - kind.base_height

    guard !color_export_options.has_color_parts || raised_depth > color_cap_thickness else {
        throw ScriptError.export_failed(
            "The black top-cap option needs raised details taller than \(three_mf_decimal(color_cap_thickness)) mm."
        )
    }

    let base_triangles = try extruded_triangles(for: outer_path, bottom_z: 0, depth: kind.base_height)
    let fill_cap_triangles = try extruded_triangles(for: fill_path, bottom_z: kind.base_height - 1.0, depth: 1.0)
    let border_full_triangles = try extruded_triangles(for: border_path, bottom_z: kind.base_height, depth: raised_depth)
    let text_full_triangles = try extruded_triangles(for: text_layout.path, bottom_z: kind.base_height, depth: raised_depth)

    let stl_triangles = merge_label_body_triangles(
        base_triangles: base_triangles,
        fill_cap_triangles: fill_cap_triangles,
        border_triangles: border_full_triangles,
        text_triangles: text_full_triangles,
        base_height: kind.base_height
    )

    guard color_export_options.has_color_parts else {
        return LabelExportGeometry(
            stl_triangles: stl_triangles,
            color_parts: [ExportPart(role: "body", triangles: stl_triangles, color: nil)],
            obj_geometry: OBJExportGeometry(triangles: stl_triangles, black_vertex_keys: [])
        )
    }

    let lower_raised_depth = raised_depth - color_cap_thickness
    let split_z = kind.top_height - color_cap_thickness

    let border_body_triangles = color_export_options.color_border
        ? try extruded_triangles(for: border_path, bottom_z: kind.base_height, depth: lower_raised_depth)
        : border_full_triangles
    let text_body_triangles = color_export_options.color_letters
        ? try extruded_triangles(for: text_layout.path, bottom_z: kind.base_height, depth: lower_raised_depth)
        : text_full_triangles

    let border_obj_triangles = color_export_options.color_border
        ? filter_top_faces(border_body_triangles, z_value: split_z)
        : border_full_triangles
    let text_obj_triangles = color_export_options.color_letters
        ? filter_top_faces(text_body_triangles, z_value: split_z)
        : text_full_triangles

    var color_parts: [ExportPart] = [
        ExportPart(
            role: "body",
            triangles: merge_label_body_triangles(
                base_triangles: base_triangles,
                fill_cap_triangles: fill_cap_triangles,
                border_triangles: border_body_triangles,
                text_triangles: text_body_triangles,
                base_height: kind.base_height
            ),
            color: .white
        )
    ]
    var obj_cap_triangles: [Triangle3D] = []
    var obj_black_vertex_keys: Set<QuantizedVertex> = []

    if color_export_options.color_letters {
        let text_cap_triangles = try extruded_triangles(for: text_layout.path, bottom_z: split_z, depth: color_cap_thickness)
        color_parts.append(ExportPart(role: "letters-cap", triangles: text_cap_triangles, color: .black))
        obj_cap_triangles.append(contentsOf: filter_bottom_faces(text_cap_triangles, z_value: split_z))
        obj_black_vertex_keys.formUnion(quantized_vertices(from: keep_top_faces(text_cap_triangles, z_value: kind.top_height)))
    }

    if color_export_options.color_border {
        let border_cap_triangles = try extruded_triangles(for: border_path, bottom_z: split_z, depth: color_cap_thickness)
        color_parts.append(ExportPart(role: "border-cap", triangles: border_cap_triangles, color: .black))
        obj_cap_triangles.append(contentsOf: filter_bottom_faces(border_cap_triangles, z_value: split_z))
        obj_black_vertex_keys.formUnion(quantized_vertices(from: keep_top_faces(border_cap_triangles, z_value: kind.top_height)))
    }

    let obj_body_triangles = merge_label_body_triangles(
        base_triangles: base_triangles,
        fill_cap_triangles: fill_cap_triangles,
        border_triangles: border_obj_triangles,
        text_triangles: text_obj_triangles,
        base_height: kind.base_height
    )

    return LabelExportGeometry(
        stl_triangles: stl_triangles,
        color_parts: color_parts,
        obj_geometry: OBJExportGeometry(
            triangles: obj_body_triangles + obj_cap_triangles,
            black_vertex_keys: obj_black_vertex_keys
        )
    )
}

func extruded_triangles(for path: NSBezierPath, bottom_z: Double, depth: Double) throws -> [Triangle3D] {
    guard depth > 0 else {
        return []
    }

    return try exported_triangles(for: path, depth: depth)
        .map { $0.translated(z: bottom_z + depth / 2.0) }
}

func merge_label_body_triangles(
    base_triangles: [Triangle3D],
    fill_cap_triangles: [Triangle3D],
    border_triangles: [Triangle3D],
    text_triangles: [Triangle3D],
    base_height: Double
) -> [Triangle3D] {
    let filtered_base = filter_base_top_faces(base_triangles, base_height: base_height)
    let filtered_fill_cap = keep_top_faces(fill_cap_triangles, z_value: base_height)
    let filtered_border = filter_bottom_faces(border_triangles, z_value: base_height)
    let filtered_text = filter_bottom_faces(text_triangles, z_value: base_height)
    return filtered_base + filtered_fill_cap + filtered_border + filtered_text
}

func error_message(for error: Error) -> String {
    if let localized_error = error as? LocalizedError, let description = localized_error.errorDescription {
        return description
    }

    return error.localizedDescription
}

func load_reference_font() throws -> CTFont {
    let font_url = URL(fileURLWithPath: "/Library/Fonts/Merriweather_BoldItalic.ttf")
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(font_url as CFURL) as? [CTFontDescriptor],
          let descriptor = descriptors.first
    else {
        throw ScriptError.missing_font(font_url)
    }

    return CTFontCreateWithFontDescriptor(descriptor, layout_font_size, nil)
}

func ensure_supported_characters(in value: String, font: CTFont) throws {
    let unsupported = value
        .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        .flatMap { token -> [String] in
            let token_string = String(token)
            return missing_glyph_fragments(in: token_string, font: font).isEmpty ? [] : [token_string]
        }

    if let first = unsupported.first {
        throw ScriptError.unsupported_characters(first)
    }
}

func missing_glyph_fragments(in value: String, font: CTFont) -> [String] {
    let utf16_values = Array(value.utf16)
    var glyphs = Array(repeating: CGGlyph(), count: utf16_values.count)
    var characters = utf16_values
    _ = CTFontGetGlyphsForCharacters(font, &characters, &glyphs, utf16_values.count)

    var missing: [String] = []
    for (index, glyph) in glyphs.enumerated() where glyph == 0 {
        let scalar_value = utf16_values[index]
        if let scalar = UnicodeScalar(scalar_value), !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            missing.append(String(scalar))
        }
    }
    return missing
}

func load_reference(kind: LabelKind, script_directory: URL) throws -> LabelReference {
    let file_manager = FileManager.default
    let candidate_urls = reference_file_candidates(
        file_name: kind.reference_file_name,
        script_directory: script_directory
    )
    guard let file_url = candidate_urls.first(where: { file_manager.fileExists(atPath: $0.path) }) else {
        throw ScriptError.reference_file_missing(candidate_urls[0])
    }

    // The shipped sample meshes are the most reliable source for the three label silhouettes and text safe areas.
    let triangles = try parse_binary_stl(at: file_url)
    guard let top_z = triangles.flatMap({ [$0.a.z, $0.b.z, $0.c.z] }).max() else {
        throw ScriptError.reference_shape_unusable(file_url)
    }

    let loops = extract_loops(at: top_z, from: triangles)
    guard loops.count >= 3 else {
        throw ScriptError.reference_shape_unusable(file_url)
    }

    let sorted_loops = loops.sorted { bounding_box(for: $0).area > bounding_box(for: $1).area }
    let outer_loop = sorted_loops[0]
    let inner_loop = sorted_loops[1]
    let text_loops = Array(sorted_loops.dropFirst(2))

    var outer_bounds = bounding_box(for: outer_loop)
    let text_bounds = text_loops.map(bounding_box(for:)).reduce(CGRect.null) { partial, bounds in
        partial.union(bounds)
    }

    guard !text_bounds.isNull else {
        throw ScriptError.reference_shape_unusable(file_url)
    }

    let offset = CGPoint(x: -outer_bounds.minX, y: -outer_bounds.minY)
    let normalized_outer = outer_loop.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
    let normalized_inner = inner_loop.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
    outer_bounds.origin = .zero
    let normalized_text_bounds = text_bounds.offsetBy(dx: offset.x, dy: offset.y)

    return LabelReference(
        kind: kind,
        outer_loop: normalized_outer,
        inner_loop: normalized_inner,
        bounds: outer_bounds,
        text_bounds: normalized_text_bounds
    )
}

func reference_file_candidates(file_name: String, script_directory: URL) -> [URL] {
    let parent_directory = script_directory.deletingLastPathComponent()
    return [
        script_directory.appendingPathComponent("example/\(file_name)"),
        script_directory.appendingPathComponent(file_name),
        script_directory.appendingPathComponent("design/\(file_name)"),
        parent_directory.appendingPathComponent("design/\(file_name)"),
    ]
}

func parse_binary_stl(at url: URL) throws -> [Triangle3D] {
    let data = try Data(contentsOf: url)
    guard data.count >= 84 else {
        throw ScriptError.reference_shape_unusable(url)
    }

    let triangle_count = Int(read_little_endian_uint32(data, at: 80))
    var triangles: [Triangle3D] = []
    triangles.reserveCapacity(triangle_count)

    var offset = 84
    for _ in 0..<triangle_count {
        guard offset + 50 <= data.count else {
            throw ScriptError.reference_shape_unusable(url)
        }

        let v1 = SIMD3<Double>(
            read_little_endian_float(data, at: offset + 12),
            read_little_endian_float(data, at: offset + 16),
            read_little_endian_float(data, at: offset + 20)
        )
        let v2 = SIMD3<Double>(
            read_little_endian_float(data, at: offset + 24),
            read_little_endian_float(data, at: offset + 28),
            read_little_endian_float(data, at: offset + 32)
        )
        let v3 = SIMD3<Double>(
            read_little_endian_float(data, at: offset + 36),
            read_little_endian_float(data, at: offset + 40),
            read_little_endian_float(data, at: offset + 44)
        )
        triangles.append(Triangle3D(a: v1, b: v2, c: v3))
        offset += 50
    }

    return triangles
}

func read_little_endian_uint32(_ data: Data, at offset: Int) -> UInt32 {
    data.withUnsafeBytes { raw_buffer in
        let pointer = raw_buffer.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt32.self)
        return UInt32(littleEndian: pointer.pointee)
    }
}

func read_little_endian_float(_ data: Data, at offset: Int) -> Double {
    data.withUnsafeBytes { raw_buffer in
        let pointer = raw_buffer.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt32.self)
        let bit_pattern = UInt32(littleEndian: pointer.pointee)
        return Double(Float(bitPattern: bit_pattern))
    }
}

func extract_loops(at z_value: Double, from triangles: [Triangle3D]) -> [[CGPoint]] {
    var edge_counts: [EdgeKey: Int] = [:]
    var point_lookup: [QuantizedPoint: CGPoint] = [:]
    let epsilon = 0.0001

    for triangle in triangles where triangle.is_horizontal(at: z_value, epsilon: epsilon) {
        let points = [
            CGPoint(x: triangle.a.x, y: triangle.a.y),
            CGPoint(x: triangle.b.x, y: triangle.b.y),
            CGPoint(x: triangle.c.x, y: triangle.c.y),
        ]
        let quantized_points = points.map(quantize)

        for (index, point) in quantized_points.enumerated() {
            point_lookup[point] = points[index]
        }

        let pairs = [(0, 1), (1, 2), (2, 0)]
        for pair in pairs {
            let edge = EdgeKey(quantized_points[pair.0], quantized_points[pair.1])
            edge_counts[edge, default: 0] += 1
        }
    }

    let boundary_edges = edge_counts.filter { $0.value == 1 }.map(\.key)
    var adjacency: [QuantizedPoint: [QuantizedPoint]] = [:]
    for edge in boundary_edges {
        adjacency[edge.start, default: []].append(edge.end)
        adjacency[edge.end, default: []].append(edge.start)
    }

    var visited: Set<EdgeKey> = []
    var loops: [[CGPoint]] = []

    for edge in boundary_edges where !visited.contains(edge) {
        var loop_points: [CGPoint] = []
        var previous: QuantizedPoint? = nil
        var current = edge.start
        let start = edge.start

        while true {
            guard let original = point_lookup[current] else {
                break
            }
            loop_points.append(original)

            let neighbors = adjacency[current, default: []].sorted()
            guard let next = neighbors.first(where: { neighbor in
                let candidate = EdgeKey(current, neighbor)
                return !visited.contains(candidate) && neighbor != previous
            }) ?? neighbors.first(where: { neighbor in
                let candidate = EdgeKey(current, neighbor)
                return !visited.contains(candidate)
            }) else {
                break
            }

            let walked_edge = EdgeKey(current, next)
            visited.insert(walked_edge)
            previous = current
            current = next

            if current == start {
                break
            }
        }

        if loop_points.count >= 3 {
            loops.append(loop_points)
        }
    }

    return loops
}

func quantize(_ point: CGPoint) -> QuantizedPoint {
    QuantizedPoint(
        x: Int((point.x * 10000.0).rounded()),
        y: Int((point.y * 10000.0).rounded())
    )
}

func bounding_box(for points: [CGPoint]) -> CGRect {
    guard let first = points.first else {
        return .null
    }

    var min_x = first.x
    var max_x = first.x
    var min_y = first.y
    var max_y = first.y

    for point in points.dropFirst() {
        min_x = min(min_x, point.x)
        max_x = max(max_x, point.x)
        min_y = min(min_y, point.y)
        max_y = max(max_y, point.y)
    }

    return CGRect(x: min_x, y: min_y, width: max_x - min_x, height: max_y - min_y)
}

func bezier_path(from loop: [CGPoint]) -> NSBezierPath {
    let path = NSBezierPath()
    guard !loop.isEmpty else {
        return path
    }

    path.move(to: loop[0])
    for point in loop.dropFirst() {
        path.line(to: point)
    }
    path.close()
    return path
}

func ring_path(outer_path: NSBezierPath, inner_path: NSBezierPath) -> NSBezierPath {
    let path = NSBezierPath()
    path.windingRule = .evenOdd
    path.append(outer_path)
    path.append(inner_path)
    return path
}

func center_fill_path(inner_path: NSBezierPath, text_path: NSBezierPath) -> NSBezierPath {
    let path = NSBezierPath()
    path.windingRule = .evenOdd
    path.append(inner_path)
    path.append(text_path)
    return path
}

func layout_text(plant_name: String, target_bounds: CGRect, font: CTFont) throws -> TextLayout {
    let candidates = unique_candidates(for: plant_name)
    var best_layout: TextLayout?
    var best_score = -Double.infinity

    for lines in candidates {
        let block = make_text_block(lines: lines, font: font)
        guard block.bounds.width > 0, block.bounds.height > 0 else {
            continue
        }

        let scale = min(target_bounds.width / block.bounds.width, target_bounds.height / block.bounds.height)
        let effective_font_size = layout_font_size * scale
        guard effective_font_size >= minimum_font_size else {
            continue
        }

        let scaled_path = transformed_copy(of: block.path, scale_x: scale, scale_y: scale)
        let centered_path = transformed_copy(
            of: scaled_path,
            translate_x: target_bounds.midX - scaled_path.bounds.midX,
            translate_y: target_bounds.midY - scaled_path.bounds.midY
        )

        let line_widths = block.line_bounds.map(\.width)
        let width_balance = line_widths.count == 2 && max(line_widths[0], line_widths[1]) > 0
            ? abs(line_widths[0] - line_widths[1]) / max(line_widths[0], line_widths[1])
            : 0.0

        let score = Double(effective_font_size)
            + (is_cultivar_split(lines: lines, original: plant_name) ? 0.35 : 0.0)
            + (lines.count == 2 ? 0.10 : 0.0)
            - Double(width_balance) * 0.25

        if score > best_score {
            best_score = score
            best_layout = TextLayout(lines: lines, path: centered_path, effective_font_size: effective_font_size)
        }
    }

    guard let best_layout else {
        throw ScriptError.name_too_long(
            "The name is too long to fit these label designs without making the text too small to print clearly. Try a shorter plant name or a shorter cultivar name."
        )
    }

    return best_layout
}

func unique_candidates(for plant_name: String) -> [[String]] {
    let normalized = normalize_name(plant_name)
    let tokens = normalized.split(separator: " ").map(String.init)
    var candidates: [[String]] = [[normalized]]

    if let cultivar_candidate = cultivar_split_candidate(for: normalized) {
        candidates.append(cultivar_candidate)
    }

    if tokens.count >= 2 {
        for split_index in 1..<tokens.count {
            let first_line = tokens[..<split_index].joined(separator: " ")
            let second_line = tokens[split_index...].joined(separator: " ")
            candidates.append([first_line, second_line])
        }
    }

    var seen: Set<String> = []
    var deduped: [[String]] = []
    for candidate in candidates {
        let key = candidate.joined(separator: "\u{241E}")
        if seen.insert(key).inserted {
            deduped.append(candidate)
        }
    }

    return deduped
}

func cultivar_split_candidate(for plant_name: String) -> [String]? {
    let quote_characters = CharacterSet(charactersIn: "\"'“”‘’")
    guard let first_quote_range = plant_name.rangeOfCharacter(from: quote_characters),
          let last_quote_range = plant_name.rangeOfCharacter(from: quote_characters, options: .backwards),
          first_quote_range.lowerBound < last_quote_range.lowerBound
    else {
        return nil
    }

    let prefix = plant_name[..<first_quote_range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    let suffix = plant_name[first_quote_range.lowerBound...].trimmingCharacters(in: .whitespacesAndNewlines)

    guard !prefix.isEmpty, !suffix.isEmpty else {
        return nil
    }

    return [String(prefix), String(suffix)]
}

func is_cultivar_split(lines: [String], original: String) -> Bool {
    guard lines.count == 2, let cultivar = cultivar_split_candidate(for: normalize_name(original)) else {
        return false
    }
    return lines == cultivar
}

func make_text_block(lines: [String], font: CTFont) -> (path: NSBezierPath, bounds: CGRect, line_bounds: [CGRect]) {
    let rendered_lines = lines.map { render_line_path($0, font: font) }
    let max_width = rendered_lines.map { $0.bounds.width }.max() ?? 0
    let line_gap = layout_font_size * line_gap_ratio
    let block = NSBezierPath()
    var y_cursor: CGFloat = 0
    var line_bounds: [CGRect] = []

    for rendered_line in rendered_lines {
        let centered_x = (max_width - rendered_line.bounds.width) / 2.0
        let placed = transformed_copy(
            of: rendered_line.path,
            translate_x: centered_x - rendered_line.bounds.minX,
            translate_y: y_cursor - rendered_line.bounds.minY
        )
        block.append(placed)
        line_bounds.append(placed.bounds)
        y_cursor -= rendered_line.bounds.height + line_gap
    }

    let normalized = transformed_copy(of: block, translate_x: -block.bounds.minX, translate_y: -block.bounds.minY)
    let normalized_line_bounds = line_bounds.map { $0.offsetBy(dx: -block.bounds.minX, dy: -block.bounds.minY) }
    return (normalized, normalized.bounds, normalized_line_bounds)
}

func render_line_path(_ line: String, font: CTFont) -> (path: NSBezierPath, bounds: CGRect) {
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font,
    ]
    let attributed = NSAttributedString(string: line, attributes: attributes)
    let ct_line = CTLineCreateWithAttributedString(attributed)
    let runs = CTLineGetGlyphRuns(ct_line) as NSArray
    let line_path = NSBezierPath()

    for run_object in runs {
        let run = run_object as! CTRun
        let glyph_count = CTRunGetGlyphCount(run)
        guard glyph_count > 0 else {
            continue
        }

        var glyphs = Array(repeating: CGGlyph(), count: glyph_count)
        var positions = Array(repeating: CGPoint.zero, count: glyph_count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)

        let run_attributes = CTRunGetAttributes(run) as NSDictionary
        let run_font = run_attributes[kCTFontAttributeName as String] as! CTFont

        for index in 0..<glyph_count {
            guard let glyph_path = CTFontCreatePathForGlyph(run_font, glyphs[index], nil) else {
                continue
            }
            let bezier = NSBezierPath(cgPath: glyph_path)
            let placed = transformed_copy(of: bezier, translate_x: positions[index].x, translate_y: positions[index].y)
            line_path.append(placed)
        }
    }

    return (line_path, line_path.bounds)
}

func transformed_copy(
    of path: NSBezierPath,
    translate_x: CGFloat = 0,
    translate_y: CGFloat = 0,
    scale_x: CGFloat = 1,
    scale_y: CGFloat = 1
) -> NSBezierPath {
    let copy = path.copy() as! NSBezierPath
    var transform = AffineTransform.identity
    transform.translate(x: translate_x, y: translate_y)
    transform.scale(x: scale_x, y: scale_y)
    copy.transform(using: transform)
    return copy
}

func exported_triangles(for path: NSBezierPath, depth: Double) throws -> [Triangle3D] {
    let flattened_path = path.copy() as! NSBezierPath
    flattened_path.flatness = geometry_flatness

    // SceneKit handles the hard part of tessellating curved 2D paths, and we convert its Collada output to STL triangles.
    let shape = SCNShape(path: flattened_path, extrusionDepth: depth)
    shape.chamferRadius = 0
    shape.firstMaterial = SCNMaterial()

    let node = SCNNode(geometry: shape)
    let scene = SCNScene()
    scene.rootNode.addChildNode(node)

    let temp_url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("dae")

    scene.write(to: temp_url, options: nil, delegate: nil, progressHandler: nil)
    defer {
        try? FileManager.default.removeItem(at: temp_url)
    }

    return try parse_collada_triangles(at: temp_url)
}

func parse_collada_triangles(at url: URL) throws -> [Triangle3D] {
    let document = try XMLDocument(contentsOf: url, options: [])
    guard let geometry = try document.nodes(forXPath: "//geometry").first as? XMLElement else {
        throw ScriptError.export_failed("The temporary Collada export did not contain any geometry.")
    }

    guard let position_input = try geometry.nodes(forXPath: ".//vertices/input[@semantic='POSITION']").first as? XMLElement,
          let position_source = position_input.attribute(forName: "source")?.stringValue?.replacingOccurrences(of: "#", with: "")
    else {
        throw ScriptError.export_failed("The temporary Collada export did not contain a position source.")
    }

    guard let positions_array = try geometry.nodes(forXPath: ".//source[@id='\(position_source)']/float_array").first as? XMLElement,
          let positions_text = positions_array.stringValue
    else {
        throw ScriptError.export_failed("The temporary Collada export did not contain vertex positions.")
    }

    let position_values = positions_text
        .split(whereSeparator: \.isWhitespace)
        .compactMap { Double($0) }

    var positions: [SIMD3<Double>] = []
    positions.reserveCapacity(position_values.count / 3)
    var index = 0
    while index + 2 < position_values.count {
        positions.append(SIMD3<Double>(position_values[index], position_values[index + 1], position_values[index + 2]))
        index += 3
    }

    let triangle_nodes = try geometry.nodes(forXPath: ".//triangles")
    var triangles: [Triangle3D] = []

    for node in triangle_nodes {
        guard let triangle_element = node as? XMLElement else {
            continue
        }

        let inputs = (try triangle_element.nodes(forXPath: "./input") as? [XMLElement]) ?? []
        let stride = (inputs.compactMap { Int($0.attribute(forName: "offset")?.stringValue ?? "0") }.max() ?? 0) + 1
        let vertex_offset = inputs.first(where: { $0.attribute(forName: "semantic")?.stringValue == "VERTEX" })
            .flatMap { Int($0.attribute(forName: "offset")?.stringValue ?? "0") } ?? 0

        guard let p_node = try triangle_element.nodes(forXPath: "./p").first as? XMLElement,
              let indices_text = p_node.stringValue
        else {
            continue
        }

        let indices = indices_text
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Int($0) }

        let triangle_stride = stride * 3
        var triangle_index = 0
        while triangle_index + triangle_stride - 1 < indices.count {
            let a_index = indices[triangle_index + vertex_offset]
            let b_index = indices[triangle_index + stride + vertex_offset]
            let c_index = indices[triangle_index + stride * 2 + vertex_offset]
            if a_index < positions.count, b_index < positions.count, c_index < positions.count {
                triangles.append(Triangle3D(a: positions[a_index], b: positions[b_index], c: positions[c_index]))
            }
            triangle_index += triangle_stride
        }
    }

    return triangles
}

func filter_base_top_faces(_ triangles: [Triangle3D], base_height: Double) -> [Triangle3D] {
    triangles.filter { triangle in
        guard triangle.is_horizontal(at: base_height) else {
            return true
        }

        return triangle.normal().z <= 0.9
    }
}

func filter_bottom_faces(_ triangles: [Triangle3D], z_value: Double) -> [Triangle3D] {
    triangles.filter { triangle in
        guard triangle.is_horizontal(at: z_value) else {
            return true
        }

        return triangle.normal().z > -0.9
    }
}

func filter_top_faces(_ triangles: [Triangle3D], z_value: Double) -> [Triangle3D] {
    triangles.filter { triangle in
        guard triangle.is_horizontal(at: z_value) else {
            return true
        }

        return triangle.normal().z < 0.9
    }
}

func keep_top_faces(_ triangles: [Triangle3D], z_value: Double) -> [Triangle3D] {
    triangles.filter { triangle in
        triangle.is_horizontal(at: z_value) && triangle.normal().z > 0.9
    }
}

func write_geometry_three_mf(parts: [ExportPart], to url: URL) throws {
    let document = try three_mf_document(from: parts)

    let temporary_root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let rels_directory = temporary_root.appendingPathComponent("_rels", isDirectory: true)
    let three_d_directory = temporary_root.appendingPathComponent("3D", isDirectory: true)

    try FileManager.default.createDirectory(at: rels_directory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: three_d_directory, withIntermediateDirectories: true)

    defer {
        try? FileManager.default.removeItem(at: temporary_root)
    }

    try write_utf8_text(three_mf_content_types_xml(), to: temporary_root.appendingPathComponent("[Content_Types].xml"))
    try write_utf8_text(three_mf_relationships_xml(), to: rels_directory.appendingPathComponent(".rels"))
    try write_utf8_text(three_mf_model_xml(document: document), to: three_d_directory.appendingPathComponent("3dmodel.model"))

    if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
    }

    try create_zip_archive(
        source_directory: temporary_root,
        destination_url: url,
        relative_paths: ["[Content_Types].xml", "_rels", "3D"]
    )
}

func three_mf_document(from parts: [ExportPart]) throws -> ThreeMFDocument {
    guard !parts.isEmpty else {
        throw ScriptError.export_failed("The 3MF export did not contain any parts to write.")
    }

    let uses_colors = parts.contains { $0.color != nil }
    let color_group = uses_colors
        ? ThreeMFColorGroup(resource_id: 1, colors: ExportColor.allCases)
        : nil

    var next_object_id = color_group == nil ? 1 : 2
    var mesh_objects: [ThreeMFMeshObject] = []
    for part in parts {
        let mesh = deduplicated_mesh(from: part.triangles)
        guard !mesh.vertices.isEmpty, !mesh.triangles.isEmpty else {
            throw ScriptError.export_failed("The 3MF part '\(part.role)' did not contain any mesh data to write.")
        }
        mesh_objects.append(
            ThreeMFMeshObject(
                object_id: next_object_id,
                mesh: mesh,
                color: part.color
            )
        )
        next_object_id += 1
    }

    if mesh_objects.count == 1 {
        return ThreeMFDocument(
            color_group: color_group,
            mesh_objects: mesh_objects,
            build_object_id: mesh_objects[0].object_id
        )
    }

    return ThreeMFDocument(
        color_group: color_group,
        mesh_objects: mesh_objects,
        build_object_id: next_object_id
    )
}

func deduplicated_mesh(from triangles: [Triangle3D]) -> Mesh3D {
    var vertices: [SIMD3<Double>] = []
    var triangles_out: [MeshTriangle] = []
    var vertex_indices: [QuantizedVertex: Int] = [:]

    func index_for_vertex(_ vertex: SIMD3<Double>) -> Int {
        let key = quantize_vertex(vertex)
        if let existing = vertex_indices[key] {
            return existing
        }

        let index = vertices.count
        vertices.append(vertex)
        vertex_indices[key] = index
        return index
    }

    for triangle in triangles {
        let indices = [
            index_for_vertex(triangle.a),
            index_for_vertex(triangle.b),
            index_for_vertex(triangle.c),
        ]

        if Set(indices).count == 3 {
            triangles_out.append(MeshTriangle(v1: indices[0], v2: indices[1], v3: indices[2]))
        }
    }

    return Mesh3D(vertices: vertices, triangles: triangles_out)
}

func quantize_vertex(_ vertex: SIMD3<Double>) -> QuantizedVertex {
    QuantizedVertex(
        x: Int64((vertex.x * 1_000_000.0).rounded()),
        y: Int64((vertex.y * 1_000_000.0).rounded()),
        z: Int64((vertex.z * 1_000_000.0).rounded())
    )
}

func quantized_vertices(from triangles: [Triangle3D]) -> Set<QuantizedVertex> {
    var vertices: Set<QuantizedVertex> = []
    for triangle in triangles {
        vertices.insert(quantize_vertex(triangle.a))
        vertices.insert(quantize_vertex(triangle.b))
        vertices.insert(quantize_vertex(triangle.c))
    }
    return vertices
}

func three_mf_content_types_xml() -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
    </Types>
    """
}

func three_mf_relationships_xml() -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
    </Relationships>
    """
}

func three_mf_model_xml(document: ThreeMFDocument) -> String {
    var resource_blocks: [String] = []

    if let color_group = document.color_group {
        resource_blocks.append(three_mf_color_group_xml(color_group: color_group))
    }

    for mesh_object in document.mesh_objects {
        resource_blocks.append(three_mf_mesh_object_xml(mesh_object: mesh_object, color_group_id: document.color_group?.resource_id))
    }

    if document.mesh_objects.count > 1 {
        let assembly_id = document.build_object_id
        let component_lines = document.mesh_objects.map { mesh_object in
            "          <component objectid=\"\(mesh_object.object_id)\"/>"
        }.joined(separator: "\n")

        resource_blocks.append(
            """
              <object id="\(assembly_id)" type="model">
                <components>
            \(component_lines)
                </components>
              </object>
            """
        )
    }

    let resource_xml = resource_blocks.joined(separator: "\n")
    let extension_attributes = document.color_group == nil
        ? ""
        : " xmlns:m=\"http://schemas.microsoft.com/3dmanufacturing/material/2015/02\" recommendedextensions=\"m\""

    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02"\(extension_attributes)>
      <resources>
    \(resource_xml)
      </resources>
      <build>
        <item objectid="\(document.build_object_id)"/>
      </build>
    </model>
    """
}

func three_mf_color_group_xml(color_group: ThreeMFColorGroup) -> String {
    let color_lines = color_group.colors.map { color in
        "      <m:color color=\"\(color.three_mf_hex)\"/>"
    }.joined(separator: "\n")

    return """
      <m:colorgroup id="\(color_group.resource_id)">
    \(color_lines)
      </m:colorgroup>
    """
}

func three_mf_mesh_object_xml(mesh_object: ThreeMFMeshObject, color_group_id: Int?) -> String {
    let vertex_lines = mesh_object.mesh.vertices.map { vertex in
        "          <vertex x=\"\(three_mf_decimal(vertex.x))\" y=\"\(three_mf_decimal(vertex.y))\" z=\"\(three_mf_decimal(vertex.z))\"/>"
    }.joined(separator: "\n")

    let triangle_lines = mesh_object.mesh.triangles.map { triangle in
        "          <triangle v1=\"\(triangle.v1)\" v2=\"\(triangle.v2)\" v3=\"\(triangle.v3)\"/>"
    }.joined(separator: "\n")
    let color_attributes: String
    if let color_group_id, let color = mesh_object.color {
        color_attributes = " pid=\"\(color_group_id)\" pindex=\"\(color.rawValue)\""
    } else {
        color_attributes = ""
    }

    return """
      <object id="\(mesh_object.object_id)" type="model"\(color_attributes)>
        <mesh>
          <vertices>
    \(vertex_lines)
          </vertices>
          <triangles>
    \(triangle_lines)
          </triangles>
        </mesh>
      </object>
    """
}

func write_obj(geometry: OBJExportGeometry, to url: URL) throws {
    let mesh = deduplicated_mesh(from: geometry.triangles)
    guard !mesh.vertices.isEmpty, !mesh.triangles.isEmpty else {
        throw ScriptError.export_failed("The OBJ export did not contain any mesh data to write.")
    }

    var lines = [
        "# Plant label OBJ export",
        "s off",
        "g label",
    ]

    for vertex in mesh.vertices {
        if geometry.includes_colors {
            let color = geometry.black_vertex_keys.contains(quantize_vertex(vertex))
                ? ExportColor.black.obj_components
                : ExportColor.white.obj_components
            lines.append(
                "v \(three_mf_decimal(vertex.x)) \(three_mf_decimal(vertex.y)) \(three_mf_decimal(vertex.z)) " +
                    "\(three_mf_decimal(color.x)) \(three_mf_decimal(color.y)) \(three_mf_decimal(color.z))"
            )
        } else {
            lines.append("v \(three_mf_decimal(vertex.x)) \(three_mf_decimal(vertex.y)) \(three_mf_decimal(vertex.z))")
        }
    }

    for triangle in mesh.triangles {
        let triangle3d = Triangle3D(
            a: mesh.vertices[triangle.v1],
            b: mesh.vertices[triangle.v2],
            c: mesh.vertices[triangle.v3]
        )
        let normal = triangle3d.normal()
        lines.append("vn \(three_mf_decimal(normal.x)) \(three_mf_decimal(normal.y)) \(three_mf_decimal(normal.z))")
    }

    for (index, triangle) in mesh.triangles.enumerated() {
        let normal_index = index + 1
        lines.append(
            "f \(triangle.v1 + 1)//\(normal_index) " +
                "\(triangle.v2 + 1)//\(normal_index) " +
                "\(triangle.v3 + 1)//\(normal_index)"
        )
    }

    try write_utf8_text(lines.joined(separator: "\n") + "\n", to: url)
}

func three_mf_decimal(_ value: Double) -> String {
    var formatted = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    while formatted.contains(".") && (formatted.hasSuffix("0") || formatted.hasSuffix(".")) {
        if formatted.hasSuffix(".") {
            formatted.removeLast()
            break
        }
        formatted.removeLast()
    }
    return formatted
}

func write_utf8_text(_ text: String, to url: URL) throws {
    guard let data = text.data(using: .utf8) else {
        throw ScriptError.export_failed("Could not encode text output as UTF-8 for \(url.lastPathComponent).")
    }
    try data.write(to: url, options: .atomic)
}

func create_zip_archive(source_directory: URL, destination_url: URL, relative_paths: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.currentDirectoryURL = source_directory
    process.arguments = ["-q", "-X", "-r", destination_url.path] + relative_paths

    let stderr_pipe = Pipe()
    process.standardError = stderr_pipe

    do {
        try process.run()
    } catch {
        throw ScriptError.export_failed("Could not start /usr/bin/zip while building the 3MF file: \(error.localizedDescription)")
    }

    process.waitUntilExit()
    let stderr_data = stderr_pipe.fileHandleForReading.readDataToEndOfFile()
    let stderr_text = String(data: stderr_data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: destination_url.path) else {
        if stderr_text.isEmpty {
            throw ScriptError.export_failed("The 3MF package could not be assembled with /usr/bin/zip.")
        }
        throw ScriptError.export_failed("The 3MF package could not be assembled with /usr/bin/zip: \(stderr_text)")
    }
}

func write_binary_stl(triangles: [Triangle3D], to url: URL, header: String) throws {
    var data = Data()
    let header_data = header.data(using: .utf8) ?? Data()
    if header_data.count >= 80 {
        data.append(header_data.prefix(80))
    } else {
        data.append(header_data)
        data.append(Data(repeating: 0, count: 80 - header_data.count))
    }

    append_little_endian(UInt32(triangles.count), to: &data)

    for triangle in triangles {
        let normal = triangle.normal()
        append_little_endian(Float(normal.x), to: &data)
        append_little_endian(Float(normal.y), to: &data)
        append_little_endian(Float(normal.z), to: &data)

        for vertex in [triangle.a, triangle.b, triangle.c] {
            append_little_endian(Float(vertex.x), to: &data)
            append_little_endian(Float(vertex.y), to: &data)
            append_little_endian(Float(vertex.z), to: &data)
        }

        append_little_endian(UInt16(0), to: &data)
    }

    try data.write(to: url, options: .atomic)
}

func append_little_endian(_ value: UInt32, to data: inout Data) {
    var little_endian = value.littleEndian
    withUnsafeBytes(of: &little_endian) { bytes in
        data.append(bytes.bindMemory(to: UInt8.self))
    }
}

func append_little_endian(_ value: UInt16, to data: inout Data) {
    var little_endian = value.littleEndian
    withUnsafeBytes(of: &little_endian) { bytes in
        data.append(bytes.bindMemory(to: UInt8.self))
    }
}

func append_little_endian(_ value: Float, to data: inout Data) {
    var little_endian = value.bitPattern.littleEndian
    withUnsafeBytes(of: &little_endian) { bytes in
        data.append(bytes.bindMemory(to: UInt8.self))
    }
}

extension CGRect {
    var area: CGFloat {
        width * height
    }
}

do {
    let exit_code = try main()
    Foundation.exit(Int32(exit_code))
} catch {
    fputs("Error: \(error_message(for: error))\n", stderr)
    Foundation.exit(1)
}
