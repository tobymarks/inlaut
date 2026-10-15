using System.Drawing;

namespace Inlaut.App;

// Physical pixel geometry, including measured text: no Graphics transform.
public readonly record struct IndicatorLayout(Size Size, Rectangle Icon, Rectangle Text, Rectangle Bars)
{
    public static IndicatorLayout Create(int dpi, Size textSize)
    {
        int Px(int value) => (int)Math.Ceiling(value * dpi / 96.0);
        int h = Math.Max(Px(48), textSize.Height + Px(24));
        int textX = Px(16 + 14 + 12);
        var text = new Rectangle(textX, (h - textSize.Height) / 2, textSize.Width, textSize.Height);
        var bars = new Rectangle(text.Right + Px(16), (h - Px(22)) / 2, Px(42), Px(22));
        return new(new Size(bars.Right + Px(16), h), new Rectangle(Px(16), (h - Px(14)) / 2, Px(14), Px(14)), text, bars);
    }
}
