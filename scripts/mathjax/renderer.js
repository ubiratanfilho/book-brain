/*! Includes MathJax 3.2.2. Copyright The MathJax Consortium. Apache-2.0. */
// Offline conversion in JavaScriptCore. Only the bundled TeX packages are available.
import { mathjax } from "mathjax-full/js/mathjax.js";
import { TeX } from "mathjax-full/js/input/tex.js";
import { SVG } from "mathjax-full/js/output/svg.js";
import { liteAdaptor } from "mathjax-full/js/adaptors/liteAdaptor.js";
import { RegisterHTMLHandler } from "mathjax-full/js/handlers/html.js";
import { SafeHandler } from "mathjax-full/js/ui/safe/SafeHandler.js";
import "mathjax-full/js/input/tex/ams/AmsConfiguration.js";

const adaptor = liteAdaptor();
SafeHandler(RegisterHTMLHandler(adaptor));

globalThis.renderEquation = (source, display) => {
  // Each equation owns its labels and operator definitions, including when chats are reopened.
  const tex = new TeX({ packages: ["base", "ams"], formatError: (_, error) => { throw error; } });
  const document = mathjax.document("", {
    InputJax: tex,
    OutputJax: new SVG({ fontCache: "none" }),
    safeOptions: { allow: { URLs: "none", classes: "none", cssIDs: "none", styles: "none" } },
  });

  // The app tints the finished image. Discard TeX-supplied paint (including SVG
  // paint-server URLs) before MathJax propagates it to children.
  tex.postFilters.add(({ data }) => {
    data.root.walkTree(node => {
      if (!node.attributes) return;
      const attrs = node.attributes.getAllAttributes();
      delete attrs.mathcolor;
      delete attrs.mathbackground;
      delete attrs.color;
      delete attrs.background;
    });
  }, -6);

  const em = display ? 18 : 14;
  const container = document.convert(source, { display, em, ex: em / 2 });
  const svg = adaptor.firstChild(container);
  if (!svg || adaptor.kind(svg) !== "svg") return null;
  const box = adaptor.getAttribute(svg, "viewBox").split(/\s+/).map(Number);
  const width = Math.ceil(box[2] * em / 1000);
  const height = Math.ceil(box[3] * em / 1000);
  if (!(width > 0 && height > 0 && width <= 16384 && height <= 2048 && width * height <= 4000000)) return null;
  adaptor.setAttribute(svg, "width", String(width));
  adaptor.setAttribute(svg, "height", String(height));
  return adaptor.outerHTML(svg);
};
