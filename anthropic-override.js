// gbrain-patchkit Anthropic SDK runtime override.
//
// Loaded via BUN_PRELOAD (exported in env.sh, sourced inside the gbrain
// shell-function wrapper). Monkey-patches @anthropic-ai/sdk's Messages
// resource so model IDs in outbound calls are swapped from
// claude-haiku-* / claude-sonnet-* to whatever GBRAIN_EXPANSION_MODEL /
// GBRAIN_SUBAGENT_MODEL points at — without modifying gbrain source.
//
// Replaces the source-patch mechanism. ~/gbrain stays untouched, git pull
// just works.
//
// Module resolution note: BUN_PRELOAD-loaded files resolve `require()`
// from the PRELOAD's directory, not the gbrain repo's. ~/.gbrain-patchkit/
// has no node_modules, so a naive `require('@anthropic-ai/sdk/...')` here
// fails silently. We use `createRequire(path.join(GBRAIN_SOURCE_DIR,
// 'package.json'))` to anchor resolution at the gbrain repo. env.sh exports
// GBRAIN_SOURCE_DIR; gbrain-patchkit migrate / onboard set it from
// `resolve_gbrain_src`.
//
// SDK shape pin: @anthropic-ai/sdk@0.30.x ships Messages at
//   node_modules/@anthropic-ai/sdk/resources/messages.js
// with a CJS export `exports.Messages` that has `.create()` and `.stream()`
// on its prototype. If a future SDK reshapes this, gbrain-patchkit doctor's
// smoke test prints the failure path.

(() => {
  const path = require('path');
  const Module = require('module');

  const sourceDir = process.env.GBRAIN_SOURCE_DIR || '';
  if (!sourceDir) {
    process.stderr.write(
      '[gbrain-patchkit] preload: GBRAIN_SOURCE_DIR unset; runtime override inactive. ' +
      'Run `gbrain-patchkit migrate` to wire it in.\n'
    );
    return;
  }

  let gbrainRequire;
  try {
    gbrainRequire = Module.createRequire(path.join(sourceDir, 'package.json'));
  } catch (e) {
    process.stderr.write(
      `[gbrain-patchkit] preload: createRequire failed for ${sourceDir}: ${e && e.message}\n`
    );
    return;
  }

  let Messages;
  try {
    Messages = gbrainRequire('@anthropic-ai/sdk/resources/messages.js').Messages;
  } catch (_e1) {
    try {
      const top = gbrainRequire('@anthropic-ai/sdk');
      Messages = top.Messages || top.default?.Messages;
    } catch (_e2) {
      // SDK not installed in this gbrain checkout; nothing to wrap.
      return;
    }
  }

  if (!Messages || typeof Messages.prototype?.create !== 'function') {
    process.stderr.write(
      '[gbrain-patchkit] preload: Messages.create not found on SDK; ' +
      'override inactive. Run `gbrain-patchkit doctor` for details.\n'
    );
    return;
  }

  const swap = (body) => {
    if (!body || typeof body !== 'object' || typeof body.model !== 'string') {
      return body;
    }
    const m = body.model;
    const env = process.env;
    if (m.includes('haiku') && env.GBRAIN_EXPANSION_MODEL) {
      return { ...body, model: env.GBRAIN_EXPANSION_MODEL };
    }
    if (m.includes('sonnet') && env.GBRAIN_SUBAGENT_MODEL) {
      return { ...body, model: env.GBRAIN_SUBAGENT_MODEL };
    }
    return body;
  };

  const wrap = (name) => {
    const orig = Messages.prototype[name];
    if (typeof orig !== 'function') return false;
    Messages.prototype[name] = function (body, ...rest) {
      return orig.call(this, swap(body), ...rest);
    };
    return true;
  };

  wrap('create');
  wrap('stream');
})();
