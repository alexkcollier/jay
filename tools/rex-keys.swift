// rex-keys.swift [--write FILE] [LAYOUT]: the tmux binds of jay's Rex workaround, made from a macOS
// keyboard layout (default com.apple.keylayout.Canadian-CSA).
//
// Rex sends each character that Option composes as Alt+<char> under modifyOtherKeys 2 (a Rex fault,
// CLAUDE.md "tmux facts"): Option+é types / and arrives as CSI 27;3;47~, which tmux reads as M-/.
// For each character that Option or Shift+Option types on the layout, the block binds M-<char>
// (M-S-<char>) to type the character, for Rex clients only (tmux's client_termtype is Rex's
// XTVERSION reply, "rex <version>"). Other terminals get the M- key as before.
//
// Print the block:                      swift tools/rex-keys.swift
// Put it into jay.conf between markers: swift tools/rex-keys.swift --write config/tmux/jay.conf
// The markers are the block's first and last lines.
import Carbon
import Foundation

let begin = "# --- Rex workaround: begin (made by tools/rex-keys.swift; do not edit by hand) ---"
let end = "# --- Rex workaround: end ---"
let isRex = "#{m:rex *,#{client_termtype}}"
// jay.conf binds these M- keys itself (Ghostty's Cmd keys, see there): a layout character with
// such a name would take them away.
let reserved: Set<String> = ["M-p", "M-P", "M-o"]

var args = Array(CommandLine.arguments.dropFirst())
var writeTo: String? = nil
if let i = args.firstIndex(of: "--write"), i + 1 < args.count {
  writeTo = args[i + 1]
  args.removeSubrange(i...(i + 1))
}
let layoutID = args.first ?? "com.apple.keylayout.Canadian-CSA"

func fail(_ msg: String) -> Never {
  FileHandle.standardError.write(("rex-keys: " + msg + "\n").data(using: .utf8)!)
  exit(1)
}

let filter = [kTISPropertyInputSourceID as String: layoutID] as CFDictionary
guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
  let source = sources.first,
  let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
else { fail("no keyboard layout \(layoutID)") }
let layoutData = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data

// The text of a key with these Carbon modifiers; nil for a dead key or no text.
func text(_ code: UInt16, _ mods: Int) -> String? {
  layoutData.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> String? in
    let layout = buf.bindMemory(to: UCKeyboardLayout.self).baseAddress!
    var dead: UInt32 = 0
    var len = 0
    var chars = [UniChar](repeating: 0, count: 8)
    let status = UCKeyTranslate(
      layout, code, UInt16(kUCKeyActionDown), UInt32((mods >> 8) & 0xff), UInt32(LMGetKbdType()),
      OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &len, &chars)
    if status != noErr || dead != 0 || len == 0 { return nil }
    return String(utf16CodeUnits: chars, count: len)
  }
}

// A tmux word for s: single quotes, or double quotes when s has one.
func quote(_ s: String) -> String {
  if !s.contains("'") { return "'" + s + "'" }
  var out = "\""
  for c in s {
    if "\"\\$#".contains(c) { out.append("\\") }
    out.append(c)
  }
  return out + "\""
}

var lines: [String] = []
var seen: Set<String> = []
var skipped: [String] = []
for (prefix, mods, plain) in [("M-", optionKey, 0), ("M-S-", optionKey | shiftKey, shiftKey)] {
  for code in UInt16(0)..<UInt16(128) {
    guard let t = text(code, mods), t.unicodeScalars.count == 1, let u = t.unicodeScalars.first
    else { continue }
    // Option composes nothing on this key (the numpad): the same text as without it, a real Alt.
    if t == text(code, plain) { continue }
    // Not text: control characters, space, no-break space (Option+Space).
    if u.value <= 0x20 || u.value == 0x7f || u.value == 0xa0 { continue }
    let key = prefix + t
    if seen.contains(key) { continue }
    seen.insert(key)
    // tmux cannot bind a private-use character (the Apple logo, U+F8FF): "unknown key".
    if (0xe000...0xf8ff).contains(u.value) || reserved.contains(key) {
      skipped.append(String(format: "%@ (U+%04X)", key, u.value))
      continue
    }
    lines.append(
      "bind -n \(quote(key)) if -F '\(isRex)' { send-keys -l \(quote(t)) } { send-keys \(quote(key)) }")
  }
}

var block = [
  begin,
  "# Rex sends each character that Option composes as Alt+<char> under modifyOtherKeys 2 (a Rex",
  "# fault, CLAUDE.md \"tmux facts\"; remove this block when Rex fixes it). For a Rex client,",
  "# M-<char> and M-S-<char> type the character that Option and Shift+Option type on the layout;",
  "# other terminals get the M- key as before. \(lines.count) keys of \(layoutID).",
]
if !skipped.isEmpty { block.append("# Not bound: " + skipped.joined(separator: ", ") + ".") }
block += lines
block.append(end)
let out = block.joined(separator: "\n") + "\n"

guard let path = writeTo else {
  print(out, terminator: "")
  exit(0)
}
guard let old = try? String(contentsOfFile: path, encoding: .utf8) else { fail("cannot read \(path)") }
guard let b = old.range(of: begin + "\n"), let e = old.range(of: end + "\n", range: b.upperBound..<old.endIndex)
else { fail("\(path) has no block between the markers") }
let new = old.replacingCharacters(in: b.lowerBound..<e.upperBound, with: out)
let tmp = path + ".rex-keys.tmp"
do {
  try new.write(toFile: tmp, atomically: false, encoding: .utf8)
  _ = rename(tmp, path)
} catch { fail("cannot write \(path)") }
FileHandle.standardError.write("rex-keys: \(lines.count) binds in \(path)\n".data(using: .utf8)!)
