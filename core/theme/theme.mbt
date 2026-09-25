///|
pub(all) struct Rgb {
  red : Byte
  green : Byte
  blue : Byte
} derive(Debug, Eq)

///|
pub(all) struct Typography {
  family : String
  size : Float
  line_height : Float
} derive(Debug, Eq)

///|
pub(all) struct Spacing {
  inset : Int
  gap : Int
  border : Int
} derive(Debug, Eq)

///|
pub(all) struct Theme {
  typography : Typography
  spacing : Spacing
  foreground : Rgb
  background : Rgb
  border : Rgb
  focus : Rgb
  error : Rgb
  disabled : Rgb
  disabled_background : Rgb
  selected : Rgb
  selection : Rgb
  status : Rgb
  error_background : Rgb
} derive(Debug, Eq)

///|
pub fn default() -> Theme {
  {
    typography: { family: "Noto Sans JP", size: 24.0F, line_height: 32.0F, },
    spacing: { inset: 8, gap: 8, border: 2, },
    foreground: { red: b'\x00', green: b'\x00', blue: b'\x00', },
    background: { red: b'\xFF', green: b'\xFF', blue: b'\xFF', },
    border: { red: b'\x35', green: b'\x50', blue: b'\x6D', },
    focus: { red: b'\xF5', green: b'\xA1', blue: b'\x5C', },
    error: { red: b'\xC4', green: b'\x3C', blue: b'\x3C', },
    disabled: { red: b'\x8A', green: b'\x8A', blue: b'\x8A', },
    disabled_background: { red: b'\xEF', green: b'\xEF', blue: b'\xEF', },
    selected: { red: b'\xD7', green: b'\xED', blue: b'\xFF', },
    selection: { red: b'\xB4', green: b'\xD2', blue: b'\xFF', },
    status: { red: b'\xE9', green: b'\xF4', blue: b'\xFF', },
    error_background: { red: b'\xFF', green: b'\xE8', blue: b'\xE8', },
  }
}

///|
pub fn Theme::valid(self : Theme) -> Bool {
  self.typography.family != "" &&
  self.typography.size >= 8.0F &&
  self.typography.size <= 64.0F &&
  self.typography.line_height >= self.typography.size &&
  self.typography.line_height <= 96.0F &&
  self.spacing.inset >= 0 &&
  self.spacing.inset <= 32 &&
  self.spacing.gap >= 0 &&
  self.spacing.gap <= 32 &&
  self.spacing.border >= 1 &&
  self.spacing.border <= 4
}
