using System.Text;
using Markdig;
using Markdig.Extensions.Tables;
using Markdig.Extensions.TaskLists;
using Markdig.Syntax;
using Markdig.Syntax.Inlines;

namespace Riff.Core;

public static class ReleaseMarkdown
{
    static readonly MarkdownPipeline Pipeline = new MarkdownPipelineBuilder().UsePipeTables().UseTaskLists().UseEmphasisExtras().UseAutoLinks().Build();
    public static string ToRtf(string markdown, Uri baseUrl, int ink = 0x302927, int accent = 0xBA382F, int inset = 0xEAE6DF, int muted = 0x706962)
    {
        static string ColorEntry(int rgb) => $@"\red{(rgb >> 16) & 255}\green{(rgb >> 8) & 255}\blue{rgb & 255};";
        var result = new StringBuilder(@"{\rtf1\ansi\deff0{\fonttbl{\f0 Segoe UI;}{\f1 Consolas;}}{\colortbl;");
        foreach (var color in new[] { ink, accent, inset, muted }) result.Append(ColorEntry(color));
        result.Append(@"}\viewkind4\uc1\f0\fs22\cf1 ");
        Blocks(Markdown.Parse(markdown, Pipeline), result, baseUrl);
        return result.Append('}').ToString();
    }
    static void Blocks(ContainerBlock blocks, StringBuilder text, Uri baseUrl, int indent = 0, string prefix = "")
    {
        foreach (var block in blocks)
        {
            switch (block)
            {
                case HtmlBlock: break;
                case HeadingBlock heading:
                    Paragraph(text, indent, 180, 140);
                    text.Append(@"\b\fs").Append(heading.Level switch { 1 => 38, 2 => 30, _ => 25 }).Append(' ');
                    Inline(heading.Inline, text, baseUrl); text.Append(@"\b0\fs22\par ");
                    break;
                case ParagraphBlock paragraph:
                    Paragraph(text, indent, 0, 130); text.Append(Escape(prefix)); prefix = "";
                    Inline(paragraph.Inline, text, baseUrl); text.Append(@"\par ");
                    break;
                case ListBlock list:
                    var number = int.TryParse(list.OrderedStart, out var start) ? start : 1;
                    foreach (var item in list.OfType<ListItemBlock>())
                        Blocks(item, text, baseUrl, indent + 300, list.IsOrdered ? $"{number++}.  " : "•  ");
                    break;
                case QuoteBlock quote:
                    text.Append(@"{\cf4 "); Blocks(quote, text, baseUrl, indent + 300); text.Append('}');
                    break;
                case CodeBlock code:
                    Paragraph(text, indent + 160, 80, 160);
                    text.Append(@"{\f1\fs20\highlight3 ").Append(Escape(code.Lines.ToString())).Append(@"}\par ");
                    break;
                case ThematicBreakBlock:
                    Paragraph(text, indent, 100, 160); text.Append(@"\brdrb\brdrs\brdrw10\brdrcf4\par ");
                    break;
                case Table table:
                    foreach (var row in table.OfType<TableRow>())
                    {
                        var cells = row.OfType<TableCell>().ToArray();
                        text.Append(@"\trowd\trgaph100 ");
                        for (var i = 0; i < cells.Length; i++) text.Append(@"\clbrdrb\brdrs\brdrw10\brdrcf4\cellx").Append((i + 1) * 8500 / Math.Max(1, cells.Length)).Append(' ');
                        foreach (var cell in cells)
                        {
                            text.Append(@"\pard\intbl\f0\fs21\cf1 "); if (row.IsHeader) text.Append(@"\b ");
                            foreach (var leaf in cell.OfType<LeafBlock>()) Inline(leaf.Inline, text, baseUrl);
                            if (row.IsHeader) text.Append(@"\b0 "); text.Append(@"\cell ");
                        }
                        text.Append(@"\row ");
                    }
                    text.Append(@"\pard\par ");
                    break;
                case ContainerBlock container: Blocks(container, text, baseUrl, indent); break;
            }
        }
    }
    static void Paragraph(StringBuilder text, int indent, int before, int after) => text.Append(@"\pard\f0\fs22\li").Append(indent).Append(@"\sb").Append(before).Append(@"\sa").Append(after).Append(' ');
    static void Inline(ContainerInline? container, StringBuilder text, Uri baseUrl)
    {
        if (container is null) return;
        foreach (var inline in container)
        {
            switch (inline)
            {
                case LiteralInline literal: text.Append(Escape(literal.Content.ToString())); break;
                case CodeInline code: text.Append(@"{\f1\fs20\highlight3 ").Append(Escape(code.Content)).Append('}'); break;
                case EmphasisInline emphasis:
                    text.Append(emphasis.DelimiterChar == '~' ? @"{\strike " : emphasis.DelimiterCount >= 2 ? @"{\b " : @"{\i ");
                    Inline(emphasis, text, baseUrl); text.Append('}'); break;
                case LinkInline link:
                    if (!link.IsImage && SafeLink(baseUrl, link.Url) is { } url)
                    {
                        text.Append(@"{\field{\*\fldinst HYPERLINK """).Append(Escape(url.AbsoluteUri.Replace("\"", "%22"))).Append(@"""}{\fldrslt{\ul\cf2 ");
                        Inline(link, text, baseUrl); text.Append("}}}");
                    }
                    else Inline(link, text, baseUrl);
                    break;
                case AutolinkInline link:
                    var value = link.Url;
                    if (SafeLink(baseUrl, value) is { } autoUrl)
                        text.Append(@"{\field{\*\fldinst HYPERLINK """).Append(Escape(autoUrl.AbsoluteUri.Replace("\"", "%22"))).Append(@"""}{\fldrslt{\ul\cf2 ").Append(Escape(value)).Append("}}}");
                    else text.Append(Escape(value));
                    break;
                case TaskList task: text.Append(Escape(task.Checked ? "☑ " : "☐ ")); break;
                case LineBreakInline line: text.Append(line.IsHard ? @"\line " : " "); break;
                case HtmlEntityInline entity: text.Append(Escape(entity.Transcoded.ToString())); break;
                case HtmlInline: break;
                case ContainerInline children: Inline(children, text, baseUrl); break;
            }
        }
    }
    public static Uri? ClickedLink(string? linkText)
    {
        var value = linkText?.Trim();
        if (value is null) return null;
        // RichEdit includes the hidden field instruction in friendly-name link notifications.
        if (value.StartsWith("HYPERLINK", StringComparison.Ordinal))
        {
            var field = value[9..].TrimStart();
            if (field.Length < 2 || field[0] != '"') return null;
            var end = field.IndexOf('"', 1);
            if (end < 0) return null;
            value = field[1..end];
        }
        return Uri.TryCreate(value, UriKind.Absolute, out var url) && url.Scheme is "https" or "http" ? url : null;
    }
    public static Uri? SafeLink(Uri baseUrl, string? value) => Uri.TryCreate(baseUrl, value, out var url) && url.Scheme is "https" or "http" ? url : null;
    static string Escape(string value)
    {
        var escaped = new StringBuilder();
        foreach (var c in value)
        {
            if (c is '\\' or '{' or '}') escaped.Append('\\').Append(c);
            else if (c == '\n') escaped.Append(@"\line ");
            else if (c == '\r') { }
            else if (c == '\t') escaped.Append(@"\tab ");
            else if (c > 127) escaped.Append(@"\u").Append((short)c).Append('?');
            else if (!char.IsControl(c)) escaped.Append(c);
        }
        return escaped.ToString();
    }
}
