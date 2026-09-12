using System.Drawing.Drawing2D;

namespace Riff.Companion;

internal static class CompanionTheme
{
    public static Riff.Core.CompanionAppearance Appearance { get; private set; } = new();
    static Riff.Core.ThemePalette Palette => Appearance.Palette;
    public static bool Dark => Appearance.Dark || Appearance.Theme == "amoled";
    public static Color Canvas => SystemInformation.HighContrast ? SystemColors.Window : Hex(Palette.Canvas);
    public static Color Surface => SystemInformation.HighContrast ? SystemColors.Window : Hex(Palette.Surface);
    public static Color Inset => SystemInformation.HighContrast ? SystemColors.Control : Hex(Palette.Inset);
    public static Color Ink => SystemInformation.HighContrast ? SystemColors.WindowText : Hex(Dark ? 0xF5F3F0 : 0x302927);
    public static Color Muted => SystemInformation.HighContrast ? SystemColors.WindowText : Mix(Ink, Surface, 0.25f);
    public static Color Accent => SystemInformation.HighContrast ? SystemColors.Highlight : Hex(Palette.Accent);
    public static Color AccentInk => SystemInformation.HighContrast ? SystemColors.HighlightText : Hex(Dark ? 0x14191D : 0xFFFFFF);
    public static Color Success => SystemInformation.HighContrast ? Ink : Hex(Dark ? 0x9FCFA8 : 0x326344);
    public static readonly Color PadInk = Hex(0x302927);
    public static readonly Color Peach = Hex(0xFFD1AD);
    public static readonly Color Purple = Hex(0xCFBFF2);
    public static readonly Color Blue = Hex(0xADD4F0);
    public static readonly Color Green = Hex(0xBFDB9E);
    static readonly System.Runtime.CompilerServices.ConditionalWeakTable<Control, Func<Color>> foregrounds = new();

    static Color Hex(int value) => Color.FromArgb((value >> 16) & 255, (value >> 8) & 255, value & 255);
    public static Color Mix(Color first, Color second, float amount) => Color.FromArgb(
        (int)(first.R + (second.R - first.R) * amount),
        (int)(first.G + (second.G - first.G) * amount),
        (int)(first.B + (second.B - first.B) * amount));

    public static void Foreground(Control control, Func<Color> color)
    {
        foregrounds.Remove(control); foregrounds.Add(control, color); control.ForeColor = color();
    }

    public static void Apply(Control root, Riff.Core.CompanionAppearance appearance)
    {
        Appearance = appearance;
        root.SuspendLayout();
        ApplyColors(root, Canvas);
        root.ResumeLayout(); root.Invalidate(true);
    }

    static void ApplyColors(Control control, Color background)
    {
        // QR codes retain their white quiet zone in every theme.
        if (control is PictureBox) return;
        if (control is RoundedCard card) background = card.IsInset ? Inset : Surface;
        control.ForeColor = foregrounds.TryGetValue(control, out var color) ? color() : Ink;
        if (control.BackColor != Color.Transparent) control.BackColor = background;
        if (control is LinkLabel link)
        {
            link.LinkColor = Accent; link.ActiveLinkColor = Accent; link.VisitedLinkColor = Muted;
        }
        foreach (Control child in control.Controls) ApplyColors(child, background);
        if (control is CompanionUpdatesView updates) updates.RefreshAppearance();
        control.Invalidate();
    }
    public static readonly Font BodyFont = new("Segoe UI", 10.5f);
    public static readonly Font StrongFont = new("Segoe UI Semibold", 10.5f);
    public static readonly Font TitleFont = new("Segoe UI", 27, FontStyle.Bold);
    public static readonly Font SectionFont = new("Segoe UI Semibold", 14);

    public static Label Label(string text, Font? font = null, Func<Color>? color = null)
    {
        var label = new Label
        {
            Text = text, AutoSize = true, Dock = DockStyle.Top, Font = font ?? BodyFont,
            BackColor = Color.Transparent, UseMnemonic = false, Margin = new(0, 0, 0, 12)
        };
        Foreground(label, color ?? (() => Ink));
        return label;
    }

    public static TableLayoutPanel Stack() => new()
    {
        AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, Dock = DockStyle.Top,
        ColumnCount = 1, RowCount = 0, Margin = Padding.Empty, BackColor = Color.Transparent,
        ColumnStyles = { new(SizeType.Percent, 100) }
    };

    public static void Add(TableLayoutPanel stack, params Control[] controls)
    {
        foreach (var control in controls)
        {
            control.Dock = DockStyle.Top;
            control.TabIndex = stack.Controls.Count;
            stack.RowStyles.Add(new(SizeType.AutoSize));
            stack.Controls.Add(control, 0, stack.RowCount++);
        }
    }

    public static FlowLayoutPanel Actions(params Control[] buttons)
    {
        var row = new FlowLayoutPanel
        {
            AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Top, Margin = Padding.Empty, BackColor = Color.Transparent
        };
        row.Controls.AddRange(buttons);
        for (var i = 0; i < buttons.Length; i++) buttons[i].TabIndex = i;
        return row;
    }

    public static RoundedCard Card(string title, params Control[] controls)
    {
        var card = new RoundedCard();
        Add(card, Label(title, SectionFont));
        Add(card, controls);
        return card;
    }

    public static Panel Page(string name, string title, string subtitle, out TableLayoutPanel content)
    {
        var page = new Panel
        {
            Name = name, AccessibleName = name, Dock = DockStyle.Fill, AutoScroll = true,
            Padding = new(32, 28, 32, 24), BackColor = Canvas
        };
        content = Stack();
        Add(content, Label(title, TitleFont), Label(subtitle, color: () => Muted));
        page.Controls.Add(content);
        return page;
    }

    public static RoundedCard Field(Control input)
    {
        var frame = new RoundedCard { IsInset = true, Padding = new(12, 10, 12, 10), Margin = new(0, 0, 0, 16) };
        input.Margin = Padding.Empty;
        input.BackColor = Inset; input.ForeColor = Ink; input.Font = BodyFont;
        if (input is TextBox text) text.BorderStyle = BorderStyle.None;
        if (input is ComboBox combo) combo.FlatStyle = FlatStyle.Flat;
        Add(frame, input);
        return frame;
    }

    public static GraphicsPath Round(RectangleF bounds, float radius)
    {
        var path = new GraphicsPath();
        var diameter = Math.Min(radius * 2, Math.Min(bounds.Width, bounds.Height));
        if (diameter <= 0) return path;
        path.AddArc(bounds.X, bounds.Y, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Y, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.X, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure(); return path;
    }
}

internal sealed class RoundedCard : TableLayoutPanel
{
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    public bool IsInset { get; init; }
    Color? customSurface;
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    public Color SurfaceColor
    {
        get => customSurface ?? (IsInset ? CompanionTheme.Inset : CompanionTheme.Surface);
        set { customSurface = value; Invalidate(); }
    }
    public RoundedCard()
    {
        DoubleBuffered = true; AutoSize = true; AutoSizeMode = AutoSizeMode.GrowAndShrink;
        ColumnCount = 1; RowCount = 0; ColumnStyles.Add(new(SizeType.Percent, 100));
        Padding = new(24, 22, 24, 12); Margin = new(0, 12, 0, 8);
        BackColor = Color.Transparent;
    }
    protected override void OnPaintBackground(PaintEventArgs e)
    {
        base.OnPaintBackground(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var shape = CompanionTheme.Round(new(0, 0, Width - 1, Height - 1), 24 * DeviceDpi / 96f);
        using var brush = new SolidBrush(SurfaceColor);
        e.Graphics.FillPath(brush, shape);
    }
}

internal sealed class RiffButton : Button
{
    bool hovered;
    bool pressed;
    bool selected;
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    public bool Primary { get; init; }
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    public bool Navigation { get; init; }
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    public Color TileColor { get; init; } = CompanionTheme.Peach;
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    public string Glyph { get; init; } = "";
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    public bool Selected
    {
        get => selected;
        set { selected = value; AccessibleDescription = value ? "Current page" : null; Invalidate(); }
    }
    public RiffButton(string title)
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.SupportsTransparentBackColor, true);
        Text = title; AccessibleName = title; UseMnemonic = false; AutoSize = true; AutoSizeMode = AutoSizeMode.GrowAndShrink;
        FlatStyle = FlatStyle.Flat; FlatAppearance.BorderSize = 0; UseVisualStyleBackColor = false;
        // ButtonBase is opaque by default; paint the parent behind our rounded corners.
        SetStyle(ControlStyles.Opaque, false);
        BackColor = Color.Transparent; ForeColor = CompanionTheme.Ink; Font = CompanionTheme.StrongFont;
        Padding = new(18, 10, 18, 10); Margin = new(0, 0, 10, 10); MinimumSize = new(0, 44);
        Cursor = Cursors.Hand;
    }
    protected override void OnMouseEnter(EventArgs e) { hovered = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hovered = pressed = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { pressed = true; Invalidate(); base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { pressed = false; Invalidate(); base.OnMouseUp(e); }
    protected override void OnKeyDown(KeyEventArgs e) { if (e.KeyCode == Keys.Space) { pressed = true; Invalidate(); } base.OnKeyDown(e); }
    protected override void OnKeyUp(KeyEventArgs e) { pressed = false; Invalidate(); base.OnKeyUp(e); }
    protected override void OnLostFocus(EventArgs e) { pressed = false; Invalidate(); base.OnLostFocus(e); }
    protected override void OnPaint(PaintEventArgs e)
    {
        var scale = DeviceDpi / 96f;
        var background = Primary ? CompanionTheme.Accent : Navigation && !Selected ? CompanionTheme.Canvas : CompanionTheme.Inset;
        if (Navigation && Selected) background = CompanionTheme.Surface;
        if (hovered && Enabled) background = Primary ? CompanionTheme.Mix(CompanionTheme.Accent, CompanionTheme.Dark ? Color.White : Color.Black, 0.10f) : CompanionTheme.Mix(background, CompanionTheme.Accent, 0.10f);
        if (pressed && Enabled) background = Primary ? CompanionTheme.Mix(CompanionTheme.Accent, CompanionTheme.Dark ? Color.White : Color.Black, 0.20f) : CompanionTheme.Mix(background, CompanionTheme.Accent, 0.18f);
        if (!Enabled) background = CompanionTheme.Inset;
        var foreground = Enabled ? Primary ? CompanionTheme.AccentInk : Navigation && Selected ? CompanionTheme.Accent : CompanionTheme.Ink : CompanionTheme.Muted;
        if (SystemInformation.HighContrast)
        {
            background = Selected || Primary ? SystemColors.Highlight : SystemColors.Control;
            foreground = !Enabled ? SystemColors.GrayText : Selected || Primary ? SystemColors.HighlightText : SystemColors.ControlText;
        }
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var shape = CompanionTheme.Round(new(0, 0, Width - 1, Height - 1), 17 * scale);
        using var brush = new SolidBrush(background);
        e.Graphics.FillPath(brush, shape);
        var textBounds = ClientRectangle;
        var flags = TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix;
        if (Navigation)
        {
            var tile = new Rectangle((int)(12 * scale), (int)((Height - 30 * scale) / 2), (int)(30 * scale), (int)(30 * scale));
            using var tileShape = CompanionTheme.Round(tile, 10 * scale);
            using var tileBrush = new SolidBrush(SystemInformation.HighContrast ? background : CompanionTheme.Appearance.Theme == "amoled" ? Color.Black : TileColor);
            e.Graphics.FillPath(tileBrush, tileShape);
            if (CompanionTheme.Appearance.Theme == "amoled" && !SystemInformation.HighContrast)
            {
                using var outline = new Pen(CompanionTheme.Mix(TileColor, Color.Black, 0.5f), scale);
                e.Graphics.DrawPath(outline, tileShape);
            }
            var iconColor = SystemInformation.HighContrast ? foreground : CompanionTheme.Appearance.Theme == "amoled" ? TileColor : CompanionTheme.PadInk;
            using var iconFont = new Font("Segoe MDL2 Assets", 12);
            TextRenderer.DrawText(e.Graphics, Glyph, iconFont, tile, iconColor, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
            textBounds.X += (int)(54 * scale); textBounds.Width -= (int)(64 * scale);
            flags |= TextFormatFlags.Left;
        }
        else flags |= TextFormatFlags.HorizontalCenter;
        TextRenderer.DrawText(e.Graphics, Text, Font, textBounds, foreground, flags);
        if (Focused && ShowFocusCues)
        {
            using var focus = new Pen(foreground, 1.5f * scale) { DashStyle = DashStyle.Dot };
            using var focusShape = CompanionTheme.Round(new(3, 3, Width - 7, Height - 7), 14 * scale);
            e.Graphics.DrawPath(focus, focusShape);
        }
    }
}
