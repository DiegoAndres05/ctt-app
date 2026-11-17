/**
 * Block document of a blog article (spec 013, data-model.md «Documento de bloques").
 *
 * The body is never HTML. The panel edits each text block as plain text with three marks
 * (`**negrita**`, `*cursiva*`, `[texto](url)`) and converts them to inline runs on save. The
 * database normalizes again, so this module is a convenience, not the security boundary.
 */

export interface InlineRun {
  text: string;
  bold?: true;
  italic?: true;
  href?: string;
}

export type BlogBlock =
  | { type: 'paragraph'; text: InlineRun[] }
  | { type: 'heading'; level: 2 | 3; text: InlineRun[] }
  | { type: 'quote'; text: InlineRun[] }
  | { type: 'list'; ordered: boolean; items: InlineRun[][] }
  | { type: 'image'; ref: string; alt: string | null; decorative: boolean };

export type BlogBlockType = BlogBlock['type'];

const ALLOWED_HREF = /^(https?:\/\/[^\s<>"]+|mailto:[^\s<>"]+)$/i;

/** Same rule as `blog_href_allowed` in the database. */
export function isAllowedHref(href: string): boolean {
  return href.length <= 2000 && ALLOWED_HREF.test(href);
}

const MARKUP = /\*\*([^*]+?)\*\*|\*([^*\s][^*]*?)\*|\[([^\]]+)\]\(([^)\s]+)\)/g;

/**
 * Converts the editor's plain-text markup into inline runs. Unclosed marks stay literal; a
 * link whose URL is not http(s) or mailto keeps only its label, as plain text.
 */
export function parseInlineMarkup(markup: string): InlineRun[] {
  const runs: InlineRun[] = [];
  let last = 0;

  const pushText = (text: string): void => {
    if (!text) {
      return;
    }
    const previous = runs.at(-1);
    if (previous && !previous.bold && !previous.italic && !previous.href) {
      previous.text += text;
    } else {
      runs.push({ text });
    }
  };

  for (const match of markup.matchAll(MARKUP)) {
    const index = match.index ?? 0;
    pushText(markup.slice(last, index));
    const [, bold, italic, label, href] = match;
    if (bold !== undefined) {
      runs.push({ text: bold, bold: true });
    } else if (italic !== undefined) {
      runs.push({ text: italic, italic: true });
    } else if (label !== undefined && href !== undefined) {
      if (isAllowedHref(href)) {
        runs.push({ text: label, href });
      } else {
        pushText(label);
      }
    }
    last = index + match[0].length;
  }
  pushText(markup.slice(last));
  return runs;
}

/** Inverse of {@link parseInlineMarkup} for runs the editor produces (one mark per run). */
export function serializeInlineMarkup(runs: readonly InlineRun[]): string {
  return runs
    .map((run) => {
      if (run.href) {
        return `[${run.text}](${run.href})`;
      }
      if (run.bold) {
        return `**${run.text}**`;
      }
      if (run.italic) {
        return `*${run.text}*`;
      }
      return run.text;
    })
    .join('');
}

export function inlineToPlainText(runs: readonly InlineRun[]): string {
  return runs.map((run) => run.text).join('');
}

function hasText(runs: readonly InlineRun[]): boolean {
  return runs.some((run) => run.text.trim() !== '');
}

/** Same rule as `blog_body_is_empty`: images alone do not make a body. */
export function isBodyEmpty(blocks: readonly BlogBlock[]): boolean {
  return !blocks.some((block) => {
    switch (block.type) {
      case 'paragraph':
      case 'heading':
      case 'quote':
        return hasText(block.text);
      case 'list':
        return block.items.some(hasText);
      default:
        return false;
    }
  });
}

/** Images of a body that would block publishing: no alt text and not decorative. */
export function imagesMissingAlt(blocks: readonly BlogBlock[]): number {
  return blocks.filter(
    (block) => block.type === 'image' && !block.decorative && !(block.alt ?? '').trim(),
  ).length;
}

/** Defensive parse of a body returned by the backend; unknown blocks are dropped. */
export function parseBlocks(value: unknown): BlogBlock[] {
  if (!Array.isArray(value)) {
    return [];
  }
  const blocks: BlogBlock[] = [];
  for (const raw of value) {
    if (typeof raw !== 'object' || raw === null) {
      continue;
    }
    const block = raw as Record<string, unknown>;
    switch (block['type']) {
      case 'paragraph':
      case 'quote':
        blocks.push({ type: block['type'], text: parseRuns(block['text']) });
        break;
      case 'heading':
        blocks.push({
          type: 'heading',
          level: block['level'] === 3 ? 3 : 2,
          text: parseRuns(block['text']),
        });
        break;
      case 'list':
        blocks.push({
          type: 'list',
          ordered: block['ordered'] === true,
          items: Array.isArray(block['items']) ? block['items'].map(parseRuns) : [],
        });
        break;
      case 'image':
        if (typeof block['ref'] === 'string') {
          blocks.push({
            type: 'image',
            ref: block['ref'],
            alt: typeof block['alt'] === 'string' ? block['alt'] : null,
            decorative: block['decorative'] === true,
          });
        }
        break;
      default:
        break;
    }
  }
  return blocks;
}

function parseRuns(value: unknown): InlineRun[] {
  if (!Array.isArray(value)) {
    return [];
  }
  const runs: InlineRun[] = [];
  for (const raw of value) {
    if (typeof raw !== 'object' || raw === null) {
      continue;
    }
    const run = raw as Record<string, unknown>;
    if (typeof run['text'] !== 'string') {
      continue;
    }
    const clean: InlineRun = { text: run['text'] };
    if (run['bold'] === true) {
      clean.bold = true;
    }
    if (run['italic'] === true) {
      clean.italic = true;
    }
    if (typeof run['href'] === 'string' && isAllowedHref(run['href'])) {
      clean.href = run['href'];
    }
    runs.push(clean);
  }
  return runs;
}
