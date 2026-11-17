import { vi } from 'vitest';
import type { InlineRun } from '../../../core/blog/models/blog-blocks';
import { emptyLocale, newBlock, type LocaleDraft } from './blog-editor.model';
import {
  hasExistingText,
  hasTranslatableText,
  inParts,
  parseSegmentHtml,
  splitIntoParts,
  toSegmentHtml,
  translateLocale,
} from './blog-translation';

/** Fake translator: uppercases text outside tags, keeps tags (like LibreTranslate html mode). */
const upper = vi.fn(async (segments: string[]) =>
  segments.map((s) =>
    s.replace(/(^|>)([^<]*)/g, (_m, a: string, b: string) => a + b.toUpperCase()),
  ),
);

function spanish(): LocaleDraft {
  const heading = { ...newBlock('heading'), level: 3 as const, markup: 'Qué ver' };
  const paragraph = {
    ...newBlock('paragraph'),
    markup: 'Visita **Cartagena** y [las islas](https://example.com/islas) & más',
  };
  const list = { ...newBlock('list'), ordered: true, itemsMarkup: 'Uno\n\n*Dos*' };
  const image = { ...newBlock('image', 'org/blog/a/x.webp'), alt: 'Murallas' };
  const decorative = { ...newBlock('image', 'org/blog/a/d.webp'), decorative: true, alt: '' };
  return {
    ...emptyLocale(),
    title: 'Qué ver en Cartagena',
    summary: 'Guía',
    seoTitle: '',
    blocks: [heading, paragraph, list, image, decorative],
  };
}

describe('segment HTML', () => {
  it('escapes text and numbers links without sending their URL', () => {
    const html = toSegmentHtml([
      { text: 'a < b & ' },
      { text: 'uno', bold: true },
      { text: 'sitio', href: 'https://secret.example' },
    ]);
    expect(html).toBe('a &lt; b &amp; <b>uno</b><a id="0">sitio</a>');
    expect(html).not.toContain('secret');
  });

  it('rebuilds runs and restores hrefs from the source', () => {
    const source: InlineRun[] = [{ text: 'Ver ' }, { text: 'islas', href: 'https://e.com/i' }];
    expect(parseSegmentHtml('See <a id="0">islands</a> & beaches < 5', source)).toEqual([
      { text: 'See ' },
      { text: 'islands', href: 'https://e.com/i' },
      { text: ' & beaches < 5' },
    ]);
  });

  it('rejects missing, extra, nested or reordered marks', () => {
    const source: InlineRun[] = [
      { text: 'a', bold: true },
      { text: 'b', italic: true },
    ];
    expect(parseSegmentHtml('a b', source)).toBeNull();
    expect(parseSegmentHtml('<i>b</i><b>a</b>', source)).toBeNull();
    expect(parseSegmentHtml('<b>a<i>b</i></b>', source)).toBeNull();
    expect(parseSegmentHtml('<b>a</b><i>b</i><b>c</b>', source)).toBeNull();
    expect(parseSegmentHtml('<b>a</b><i>b</i>', source)).toEqual([
      { text: 'a', bold: true },
      { text: 'b', italic: true },
    ]);
  });
});

describe('translateLocale', () => {
  it('translates fields and body keeping blocks, images and links (FR-002, FR-003)', async () => {
    upper.mockClear();
    const result = await translateLocale(spanish(), emptyLocale(), 'replace', upper);

    expect(upper).toHaveBeenCalledTimes(1);
    expect(result.title).toBe('QUÉ VER EN CARTAGENA');
    expect(result.summary).toBe('GUÍA');
    expect(result.seoTitle).toBe('');
    expect(result.blocks.map((b) => b.type)).toEqual([
      'heading',
      'paragraph',
      'list',
      'image',
      'image',
    ]);
    expect(result.blocks[0].level).toBe(3);
    expect(result.blocks[1].markup).toBe(
      'VISITA **CARTAGENA** Y [LAS ISLAS](https://example.com/islas) & MÁS',
    );
    expect(result.blocks[2]).toMatchObject({ ordered: true, itemsMarkup: 'UNO\n*DOS*' });
    expect(result.blocks[3]).toMatchObject({ ref: 'org/blog/a/x.webp', alt: 'MURALLAS' });
    expect(result.blocks[4]).toMatchObject({ decorative: true, alt: '' });
  });

  it('falls back to run-by-run plain translation when marks are lost', async () => {
    const lossy = vi.fn(async (segments: string[]) =>
      segments.map((s) => s.replace(/<[^>]+>/g, '').toUpperCase()),
    );
    const source = {
      ...emptyLocale(),
      blocks: [{ ...newBlock('paragraph'), markup: 'Ver **sol** hoy' }],
    };
    const result = await translateLocale(source, emptyLocale(), 'replace', lossy);

    expect(lossy).toHaveBeenCalledTimes(2);
    expect(lossy.mock.calls[1][0]).toEqual(['Ver', 'sol', 'hoy']);
    expect(result.blocks[0].markup).toBe('VER **SOL** HOY');
  });

  it('fill mode keeps existing target text and body (FR-008)', async () => {
    const target = {
      ...emptyLocale(),
      title: 'My own title',
      blocks: [{ ...newBlock('paragraph'), markup: 'Mine' }],
    };
    const result = await translateLocale(spanish(), target, 'fill', upper);
    expect(result.title).toBe('My own title');
    expect(result.summary).toBe('GUÍA');
    expect(result.blocks).toHaveLength(1);
    expect(result.blocks[0].markup).toBe('Mine');
  });

  it('rejects without partial results when the translator fails (FR-006)', async () => {
    const failing = vi.fn(async () => Promise.reject(new Error('down')));
    await expect(translateLocale(spanish(), emptyLocale(), 'replace', failing)).rejects.toThrow(
      'down',
    );
  });

  it('detects empty sources and existing targets', () => {
    expect(hasTranslatableText(emptyLocale())).toBe(false);
    expect(hasTranslatableText(spanish())).toBe(true);
    expect(hasExistingText(emptyLocale())).toBe(false);
    expect(hasExistingText({ ...emptyLocale(), seoTitle: 'x' })).toBe(true);
  });
});

describe('parts', () => {
  it('splits by segment count and characters without cutting a segment', () => {
    const many = Array.from({ length: 85 }, (_, i) => `s${i}`);
    expect(splitIntoParts(many).map((p) => p.length)).toEqual([40, 40, 5]);
    const long = ['a'.repeat(3000), 'b'.repeat(3000), 'c'];
    expect(splitIntoParts(long).map((p) => p.length)).toEqual([1, 2]);
  });

  it('sends parts in order and reports progress', async () => {
    const calls: string[][] = [];
    const progress: string[] = [];
    const fn = inParts(
      async (segments) => {
        calls.push(segments);
        return segments.map((s) => s.toUpperCase());
      },
      (done, total) => progress.push(`${done}/${total}`),
    );
    const input = Array.from({ length: 45 }, (_, i) => `t${i}`);
    const out = await fn(input);
    expect(calls).toHaveLength(2);
    expect(out).toEqual(input.map((s) => s.toUpperCase()));
    expect(progress).toEqual(['0/2', '1/2', '2/2']);
  });
});
