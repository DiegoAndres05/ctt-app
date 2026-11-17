import {
  imagesMissingAlt,
  isBodyEmpty,
  parseBlocks,
  parseInlineMarkup,
  serializeInlineMarkup,
  type BlogBlock,
} from './blog-blocks';

describe('parseInlineMarkup', () => {
  it('converts bold, italic and links into runs', () => {
    expect(
      parseInlineMarkup('Visita **Getsemaní** y *San Diego* en [el mapa](https://example.com/m).'),
    ).toEqual([
      { text: 'Visita ' },
      { text: 'Getsemaní', bold: true },
      { text: ' y ' },
      { text: 'San Diego', italic: true },
      { text: ' en ' },
      { text: 'el mapa', href: 'https://example.com/m' },
      { text: '.' },
    ]);
  });

  it('round-trips what the editor produces', () => {
    const markup = 'Hola **mundo**, *cursiva* y [enlace](mailto:hola@example.com)';
    expect(serializeInlineMarkup(parseInlineMarkup(markup))).toBe(markup);
  });

  it('keeps a javascript: link as plain text', () => {
    expect(parseInlineMarkup('Haz [clic](javascript:alert) aquí')).toEqual([
      { text: 'Haz clic aquí' },
    ]);
    expect(parseInlineMarkup('[x](javascript:alert(1))').some((run) => 'href' in run)).toBe(false);
  });

  it('leaves an unclosed mark literal', () => {
    expect(parseInlineMarkup('precio **sin cerrar')).toEqual([{ text: 'precio **sin cerrar' }]);
  });

  it('keeps HTML as literal text', () => {
    expect(parseInlineMarkup('<b>hola</b>')).toEqual([{ text: '<b>hola</b>' }]);
  });
});

describe('isBodyEmpty', () => {
  it('treats a body with only spaces or only images as empty', () => {
    const blocks: BlogBlock[] = [
      { type: 'paragraph', text: [{ text: '   ' }] },
      { type: 'image', ref: 'org/blog/a/x.webp', alt: 'Foto', decorative: false },
    ];
    expect(isBodyEmpty(blocks)).toBe(true);
    expect(isBodyEmpty([])).toBe(true);
  });

  it('counts headings, quotes and list items as text', () => {
    expect(isBodyEmpty([{ type: 'list', ordered: false, items: [[{ text: 'uno' }]] }])).toBe(false);
    expect(isBodyEmpty([{ type: 'heading', level: 2, text: [{ text: 'Título' }] }])).toBe(false);
  });
});

describe('imagesMissingAlt', () => {
  it('counts images without alt that are not decorative', () => {
    expect(
      imagesMissingAlt([
        { type: 'image', ref: 'a', alt: null, decorative: false },
        { type: 'image', ref: 'b', alt: ' ', decorative: false },
        { type: 'image', ref: 'c', alt: null, decorative: true },
        { type: 'image', ref: 'd', alt: 'ok', decorative: false },
      ]),
    ).toBe(2);
  });
});

describe('parseBlocks', () => {
  it('drops unknown blocks and disallowed links', () => {
    expect(
      parseBlocks([
        { type: 'script', text: 'alert(1)' },
        { type: 'paragraph', text: [{ text: 'x', href: 'javascript:alert(1)' }] },
        { type: 'heading', level: 7, text: [] },
      ]),
    ).toEqual([
      { type: 'paragraph', text: [{ text: 'x' }] },
      { type: 'heading', level: 2, text: [] },
    ]);
  });
});
