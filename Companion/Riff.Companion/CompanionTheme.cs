using System.Drawing.Drawing2D;

namespace Riff.Companion;

// The Warm palette is shared with Riff/Design/Theme.swift.
internal static class CompanionTheme
{
    public static readonly Color Canvas = ColorTranslator.FromHtml("#F6F3EE");
    public static readonly Color Surface = Color.White;
    public static readonly Color Inset = ColorTranslator.FromHtml("#EAE6DF");
    public static readonly Color Ink = ColorTranslator.FromHtml("#302927");
    public static readonly Color Muted = ColorTranslator.FromHtml("#706962");
    public static readonly Color Accent = ColorTranslator.FromHtml("#BA382F");
    public static readonly Color Peach = ColorTranslator.FromHtml("#FFE2CD");
    public static readonly Color Purple = ColorTranslator.FromHtml("#CEC0F2");
    public static readonly Color Blue = ColorTranslator.FromHtml("#ADD4EF");
    public static readonly Color Green = ColorTranslator.FromHtml("#C0DB9E");
    public static readonly Font BodyFont = new("Segoe UI", 10.5f);
    public static readonly Font StrongFont = new("Segoe UI Semibold", 10.5f);
    public static readonly Font TitleFont = new("Segoe UI", 27, FontStyle.Bold);
    public static readonly Font SectionFont = new("Segoe UI Semibold", 14);

    public static Label Label(string text, Font? font = null, Color? color = null) => new()
    {
        Text = text, AutoSize = true, Dock = DockStyle.Top, Font = font ?? BodyFont,
        ForeColor = color ?? Ink, BackColor = Color.Transparent, UseMnemonic = false,
        Margin = new(0, 0, 0, 12)
    };

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
        Add(content, Label(title, TitleFont), Label(subtitle, color: Muted));
        page.Controls.Add(content);
        return page;
    }

    public static RoundedCard Field(Control input)
    {
        var frame = new RoundedCard { SurfaceColor = Inset, Padding = new(12, 10, 12, 10), Margin = new(0, 0, 0, 16) };
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
    public Color SurfaceColor { get; set; } = CompanionTheme.Surface;
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
        if (hovered && Enabled) background = Primary ? ColorTranslator.FromHtml("#A52E26") : CompanionTheme.Peach;
        if (pressed && Enabled) background = Primary ? ColorTranslator.FromHtml("#8F2922") : ColorTranslator.FromHtml("#F4CFB4");
        if (!Enabled) background = CompanionTheme.Inset;
        var foreground = Enabled ? Primary ? Color.White : CompanionTheme.Ink : CompanionTheme.Muted;
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
            using var tileBrush = new SolidBrush(SystemInformation.HighContrast ? background : TileColor);
            e.Graphics.FillPath(tileBrush, tileShape);
            using var iconFont = new Font("Segoe MDL2 Assets", 12);
            TextRenderer.DrawText(e.Graphics, Glyph, iconFont, tile, foreground, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
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
