# Draws the package logo with hexSticker.
#
# Usage (from the package root):
#   Rscript tools/hexsticker.R
#
# Writes man/figures/logo.png (used by README.md and the pkgdown site).
# Needs the hexSticker and ggplot2 packages. Fonts come from the system; on
# other platforms set the two paths below to any bold sans and monospace font.
#
# This directory is listed in .Rbuildignore and is not part of the built
# package.

library(ggplot2)
library(hexSticker)

pdf(NULL)  # keep Rscript from leaving an Rplots.pdf behind

font_dir <- file.path(Sys.getenv("WINDIR", "C:/Windows"), "Fonts")
sysfonts::font_add("logo-sans", file.path(font_dir, "seguisb.ttf"))
sysfonts::font_add("logo-mono", file.path(font_dir, "consolab.ttf"))

navy <- "#14213D"   # hexagon fill
glaze <- "#F9A8C4"  # the glaze: border, drips and droplet
cream <- "#FFF4E0"  # text

# hexSticker draws the hexagon with radius 1 around (1, 1). The artwork below
# uses the same coordinates (the subplot covers x and y from 0 to 2), so the
# glaze can follow the upper edges of the hexagon exactly.
hex_top <- data.frame(x = c(0.134, 0.134, 1, 1.866, 1.866),
                      y = c(1.36, 1.5, 2, 1.5, 1.36))

# One drip: a strip hanging from `top` that ends in a half circle.
drip <- function(x, width, length, top = 1.37, n = 40) {
  r <- width / 2
  theta <- seq(pi, 2 * pi, length.out = n)
  data.frame(x = c(x - r, x + r * cos(theta), x + r),
             y = c(top, top - length + r * sin(theta), top))
}
drips <- list(
  drip(0.245, 0.20, 0.17), drip(0.485, 0.20, 0.36), drip(0.735, 0.20, 0.22),
  drip(1.000, 0.20, 0.37), drip(1.265, 0.20, 0.19), drip(1.515, 0.20, 0.33),
  drip(1.755, 0.20, 0.15)
)
circle <- function(x, y, r, n = 60) {
  theta <- seq(0, 2 * pi, length.out = n)
  data.frame(x = x + r * cos(theta), y = y + r * sin(theta))
}
droplet <- circle(1, 0.745, 0.058)                     # falls between the braces
shine <- data.frame(x = c(0.50, 0.66), xend = c(0.62, 0.90),
                    y = c(1.56, 1.70), yend = c(1.63, 1.84))

art <- ggplot() +
  geom_polygon(aes(x, y), data = hex_top, fill = glaze) +
  lapply(drips, function(d) geom_polygon(aes(x, y), data = d, fill = glaze)) +
  geom_polygon(aes(x, y), data = droplet, fill = glaze) +
  geom_segment(aes(x = x, y = y, xend = xend, yend = yend), data = shine,
               colour = "white", alpha = 0.6, linewidth = 1.6, lineend = "round") +
  annotate("text", x = c(0.66, 1.34), y = 0.76, label = c("{", "}"),
           family = "logo-mono", colour = cream, size = 22) +
  coord_fixed(xlim = c(0, 2), ylim = c(0, 2), expand = FALSE, clip = "off") +
  theme_void() +
  theme_transparent()

dir.create(file.path("man", "figures"), recursive = TRUE, showWarnings = FALSE)
sticker(
  art,
  package = "glazelite", p_family = "logo-sans", p_size = 19, p_color = cream,
  p_x = 1, p_y = 0.42,
  s_x = 1, s_y = 1, s_width = 2, s_height = 2,
  h_fill = navy, h_color = glaze, h_size = 1.4,
  white_around_sticker = FALSE,
  filename = file.path("man", "figures", "logo.png"), dpi = 300
)
