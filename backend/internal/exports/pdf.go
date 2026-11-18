package exports

import (
	"bytes"
	"compress/zlib"
	"fmt"
	"strings"
)

// A small PDF writer: A4 pages, Helvetica and Helvetica-Bold (built into
// every PDF reader, so nothing is embedded), text, lines and filled boxes.
// Text uses WinAnsi, which covers Western European languages and the euro
// sign; other characters print as "?". The CSV export keeps full Unicode.

const (
	pageW = 595.28 // A4 in points
	pageH = 841.89
)

type rgb [3]float64

var (
	black   = rgb{0.12, 0.16, 0.16} // onSurface #1F2A29
	muted   = rgb{0.36, 0.42, 0.41} // #5C6B69
	primary = rgb{0.17, 0.44, 0.43} // #2C706E
	income  = rgb{0.18, 0.47, 0.20} // #2F7734 (small text)
	expense = rgb{0.73, 0.07, 0.13} // #BA1120
	rule    = rgb{0.85, 0.83, 0.80}
	shade   = rgb{0.95, 0.94, 0.91}
)

type pdfDoc struct {
	pages []*bytes.Buffer
	cur   *bytes.Buffer
}

func (d *pdfDoc) addPage() {
	d.cur = &bytes.Buffer{}
	d.pages = append(d.pages, d.cur)
}

// y is measured from the top of the page, like a screen.
func (d *pdfDoc) text(x, y, size float64, bold bool, c rgb, s string) {
	font := "F1"
	if bold {
		font = "F2"
	}
	fmt.Fprintf(d.cur, "BT %.3f %.3f %.3f rg /%s %.1f Tf %.2f %.2f Td (%s) Tj ET\n",
		c[0], c[1], c[2], font, size, x, pageH-y, escape(winAnsi(s)))
}

func (d *pdfDoc) textRight(right, y, size float64, bold bool, c rgb, s string) {
	d.text(right-textWidth(s, size, bold), y, size, bold, c, s)
}

func (d *pdfDoc) line(x1, y1, x2, y2, width float64, c rgb) {
	fmt.Fprintf(d.cur, "%.3f %.3f %.3f RG %.2f w %.2f %.2f m %.2f %.2f l S\n",
		c[0], c[1], c[2], width, x1, pageH-y1, x2, pageH-y2)
}

// box fills a rectangle whose top-left corner is (x, y).
func (d *pdfDoc) box(x, y, w, h float64, c rgb) {
	fmt.Fprintf(d.cur, "%.3f %.3f %.3f rg %.2f %.2f %.2f %.2f re f\n", c[0], c[1], c[2], x, pageH-y-h, w, h)
}

// bytes writes the file: catalog, page tree, two fonts, then a page object
// and a compressed content stream per page, and the cross-reference table.
func (d *pdfDoc) bytes() []byte {
	var out bytes.Buffer
	offsets := []int{0}
	obj := func(body string) {
		offsets = append(offsets, out.Len())
		fmt.Fprintf(&out, "%d 0 obj\n%s\nendobj\n", len(offsets)-1, body)
	}
	out.WriteString("%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
	kids := make([]string, len(d.pages))
	for i := range d.pages {
		kids[i] = fmt.Sprintf("%d 0 R", 5+2*i)
	}
	obj("<< /Type /Catalog /Pages 2 0 R >>")
	obj(fmt.Sprintf("<< /Type /Pages /Kids [%s] /Count %d >>", strings.Join(kids, " "), len(d.pages)))
	obj("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
	obj("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
	for i, p := range d.pages {
		obj(fmt.Sprintf("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.2f %.2f] "+
			"/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents %d 0 R >>", pageW, pageH, 6+2*i))
		var z bytes.Buffer
		w := zlib.NewWriter(&z)
		_, _ = w.Write(p.Bytes())
		_ = w.Close()
		offsets = append(offsets, out.Len())
		fmt.Fprintf(&out, "%d 0 obj\n<< /Length %d /Filter /FlateDecode >>\nstream\n", len(offsets)-1, z.Len())
		out.Write(z.Bytes())
		out.WriteString("\nendstream\nendobj\n")
	}
	xref := out.Len()
	fmt.Fprintf(&out, "xref\n0 %d\n0000000000 65535 f \n", len(offsets))
	for _, o := range offsets[1:] {
		fmt.Fprintf(&out, "%010d 00000 n \n", o)
	}
	fmt.Fprintf(&out, "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n", len(offsets), xref)
	return out.Bytes()
}

// winAnsi maps text to the WinAnsi (cp1252) bytes the fonts use.
func winAnsi(s string) string {
	var b strings.Builder
	for _, r := range s {
		switch {
		case r == '\n' || r == '\r' || r == '\t':
			b.WriteByte(' ')
		case r >= 0x20 && r < 0x7f, r >= 0xa0 && r <= 0xff:
			b.WriteByte(byte(r))
		default:
			if c, ok := cp1252[r]; ok {
				b.WriteByte(c)
			} else {
				b.WriteByte('?')
			}
		}
	}
	return b.String()
}

var cp1252 = map[rune]byte{
	'€': 0x80, '‚': 0x82, 'ƒ': 0x83, '„': 0x84, '…': 0x85, '†': 0x86, '‡': 0x87, 'ˆ': 0x88,
	'‰': 0x89, 'Š': 0x8a, '‹': 0x8b, 'Œ': 0x8c, 'Ž': 0x8e, '‘': 0x91, '’': 0x92, '“': 0x93,
	'”': 0x94, '•': 0x95, '–': 0x96, '—': 0x97, '˜': 0x98, '™': 0x99, 'š': 0x9a, '›': 0x9b,
	'œ': 0x9c, 'ž': 0x9e, 'Ÿ': 0x9f, '−': '-',
}

func escape(s string) string {
	r := strings.NewReplacer(`\`, `\\`, `(`, `\(`, `)`, `\)`)
	return r.Replace(s)
}

// Helvetica glyph widths (1/1000 em) for ASCII 32..126, from the standard
// font metrics. Other characters count as 556 (a digit's width).
var helvetica = [95]int{
	278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
	556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
	1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
	667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
	333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
	556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
}

func textWidth(s string, size float64, bold bool) float64 {
	total := 0
	for _, c := range []byte(winAnsi(s)) {
		w := 556
		if c >= 32 && c <= 126 {
			w = helvetica[c-32]
		}
		total += w
	}
	if bold {
		total = total * 106 / 100 // bold is a little wider; close enough for layout
	}
	return float64(total) * size / 1000
}

// fit shortens s with "…" until it is at most width wide.
func fit(s string, width, size float64, bold bool) string {
	if textWidth(s, size, bold) <= width {
		return s
	}
	r := []rune(s)
	for len(r) > 0 && textWidth(string(r)+"…", size, bold) > width {
		r = r[:len(r)-1]
	}
	return strings.TrimRight(string(r), " ") + "…"
}
