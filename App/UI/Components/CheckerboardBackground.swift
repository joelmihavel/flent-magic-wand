import SwiftUI

/// Checkerboard pattern to indicate transparency in processed images.
struct CheckerboardBackground: View {
    let tileSize: CGFloat = 10
    let lightColor = Color(white: 0.92)
    let darkColor = Color(white: 0.82)

    var body: some View {
        Canvas { context, size in
            let rows = Int(ceil(size.height / tileSize))
            let cols = Int(ceil(size.width / tileSize))

            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * tileSize,
                        y: CGFloat(row) * tileSize,
                        width: tileSize,
                        height: tileSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isLight ? lightColor : darkColor)
                    )
                }
            }
        }
    }
}
