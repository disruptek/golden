#import plotly
import nimetry

import running
import temp

proc consolePlot*(stat: RunningStat; histogram: seq[int];
                  dimensions: ClassDimensions): string =
  ## create a simple plot for display on the console via kitty
  result = createTemporaryFile("-image", ".png")
  var
    data: seq[XY]
    p: Plot = newPlot(1600, 1600)

  # use this to rescale small values
  var m: float64 = 1.0
  while stat.min * m < 1:
    m *= 10.0

  p.setX(stat.min.float * m, stat.max.float * m)
  p.setY(min(histogram).float * 0.8, max(histogram).float)
  p.setXtic(dimensions.size * m)
  p.setYtic(max(histogram).float / 10.0)

  for class, value in histogram.pairs:
    # the X value is the minimum plus (the class * the class size)
    # the Y value is simply the count in the histogram
    data.add (m * (stat.min.float + (class.float * dimensions.size)), value.float)
  p.setTitle("benchmark")
  p.setFontTtf("fonts/Vera.ttf") # sorry!
  p.addPlot(data, Line, rgba(0, 0, 255, 255))
  p.save(result)
