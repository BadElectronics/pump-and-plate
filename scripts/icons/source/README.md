# App icon source

The Pump and Plate icon ("B3": a 45 lb plate with a crossed fork and knife) is
drawn as vectors in `art.js` and rendered in a browser from `render.html`.

- `render.html?mode=single&k=b3` draws the full 1024 icon on red.
- `render.html?mode=single&k=b3&nobg=1` draws it without the red background
  (the Android adaptive-icon foreground).
- `render.html?mode=sheet&set=b,b2,b3` shows the variants side by side.

The PNGs in `../ios` and `../res`, and the website icons in `site/`, were made
from those two renders. On Android the design is scaled to 88% of the visible
72dp circle of the 108dp layer, so no launcher shape crops it; the monochrome
(themed) icon keeps only the dark outlines and white lettering.

Font: Archivo Black (SIL Open Font License 1.1).
