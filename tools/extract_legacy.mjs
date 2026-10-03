import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

// 只执行仓库自己的源码，停用浏览器启动入口，不加载外部代码或资源。
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// Git 在 Windows 上可能转换换行；使用规范换行保证跨平台提取一致。
const source = fs.readFileSync(path.join(root, '宠物养成游戏.html'), 'utf8').replace(/\r\n/g, '\n');
const sourceHash = crypto.createHash('sha256').update(source).digest('hex');
let script = source.match(/<script>([\s\S]*?)<\/script>/)?.[1];
if (!script || !script.includes('  boot();')) throw new Error('原版启动入口变化，请人工审核提取器');
script = script.replace('  boot();', `
  globalThis.legacy = {
    catalog: {SPECIES, SHOP, DECOS, WEAR, WEAR_SLOTS, WEAR_BACK, GACHA, POINT_SHOP,
      THEMES, STATS, PLACE, DECO_PLACE, MENU, BANNERS, RL_SKILLS,
      constants: {TICK_MS, WORK_CD, MAX_PETS, PET_RATE, PITY_SMALL, PITY_BIG,
        SPOOK_AT_PITY, SPOOK_RATE, PULL_1, PULL_10, DUP_PET_PTS, DUP_DECO_PTS,
        DUP_WEAR_PTS, DEATH_TICKS, REVIVE_COST, REVIVE_SHARDS, SHARDS_ON_DEATH,
        REVIVE_MIN_LV, RL_CHEST_RATE, RL_CHEST_CREDITS, RL_GOLD_RATE,
        RL_CLEAR_BONUS, RL_WELCOME, RL_COST, POOP_MS, POOP_WARN_MS, POOP_MAX}},
    PX, PLACE, WEAR, MENU, SPECIES, THEMES, pxPetAt, pxWear, drawMenuIcon, pxPoop, pxBathTub, pxBathFront,
    pxRoom, pxDraw, pxResize, makePet, defaultState,
    reset: () => {state = defaultState(); PX.hearts = []; PX.bath = 0;
      PX.bathBubbles = []; PX.bathSplash = []; PX.face = 'ok'; PX.dir = 1;
      PX.hop = 0; PX.bob = false; PX.t = 0; PX.pick = ''; PX.hover = '';
      PX.annoy = 0; PX.landT = 0; PX.petDrag = null; return state;},
    theme: key => {state.theme = key; appliedTheme = ''; applyTheme(key);},
    dimensions: () => ({width: PXW, height: PXH}),
    error: () => PX.err
  };`);
const fixedNow = 1_790_985_600_000;
class FixedDate extends Date {constructor(...args) {super(...(args.length ? args : [fixedNow]));} static now() {return fixedNow;}}
const context = vm.createContext({
  Date: FixedDate,
  document: {addEventListener() {}, getElementById() {return null;},
    documentElement: {style: {setProperty() {}}}, body: {setAttribute() {}}},
  window: {innerWidth: 1120, innerHeight: 960},
});
vm.runInContext(script, context, {timeout: 5000});
const api = context.legacy;

// 将 Canvas 的平移/缩放展开为与引擎无关的有序矩形指令。
function recorder() {
  let state = {sx: 1, sy: 1, tx: 0, ty: 0, alpha: 1, fill: '#000000'};
  const stack = [], commands = [];
  const color = value => {
    if (value.startsWith('#')) {
      let hex = value.slice(1);
      if (hex.length === 3) hex = [...hex].map(c => c + c).join('');
      return [0, 2, 4].map(i => parseInt(hex.slice(i, i + 2), 16) / 255).concat(state.alpha);
    }
    const match = value.match(/^rgba?\(([^)]+)\)$/);
    if (!match) throw new Error('不支持的原版颜色：' + value);
    const numbers = match[1].split(',').map(Number);
    return numbers.slice(0, 3).map(n => n / 255).concat((numbers[3] ?? 1) * state.alpha);
  };
  return {
    commands,
    get fillStyle() {return state.fill;}, set fillStyle(v) {if (typeof v === 'string') state.fill = v;},
    get globalAlpha() {return state.alpha;}, set globalAlpha(v) {state.alpha = v;},
    save() {stack.push({...state});},
    restore() {if (!stack.length) throw new Error('Canvas restore 不匹配'); state = stack.pop();},
    translate(x, y) {state.tx += x * state.sx; state.ty += y * state.sy;},
    scale(x, y) {state.sx *= x; state.sy *= y;},
    clearRect() {},
    fillRect(x, y, w, h) {
      const x1 = x * state.sx + state.tx, y1 = y * state.sy + state.ty;
      const x2 = (x + w) * state.sx + state.tx, y2 = (y + h) * state.sy + state.ty;
      if (!w || !h) return;
      const values = [Math.min(x1, x2), Math.min(y1, y2), Math.abs(x2-x1), Math.abs(y2-y1), ...color(state.fill)];
      if (!values.every(Number.isFinite)) throw new Error('Canvas 指令含非有限数值');
      commands.push(values.map(n => Math.round(n * 1e9) / 1e9));
    },
  };
}
function capture(draw) {
  const ctx = recorder(); api.PX.ctx = ctx; draw();
  if (api.error()) throw new Error('原版绘制失败：' + api.error());
  return ctx.commands;
}
const art = {pets: {}, furniture: {}, wear: {}, icons: {}, rooms: {}, effects: {}};
for (const key of Object.keys(api.SPECIES)) {
  art.pets[key] = {};
  for (let stage = 0; stage < 4; stage++) for (const pose of ['awake', 'sleep', 'happy', 'sick', 'annoy']) {
    art.pets[key][`${stage}_${pose}`] = capture(() => api.pxPetAt(0, 0, key, stage,
      {awake: pose !== 'sleep', happy: pose === 'happy', sick: pose === 'sick', annoy: pose === 'annoy', dir: 1}));
  }
}
for (const [key, value] of Object.entries(api.PLACE)) art.furniture[key] = capture(() => value.draw(0, 0, 1));
for (const key of Object.keys(api.WEAR)) art.wear[key] = capture(() => api.pxWear(0, -27, 0, key, 1));
for (const menu of api.MENU) art.icons[menu.key] = capture(() => api.drawMenuIcon(menu.key, 0, 0, '#dCE8C4'));
art.effects.poop = capture(() => api.pxPoop(0, 0, 1));
art.effects.bath_back = capture(() => api.pxBathTub(0, 0, 1));
art.effects.bath_front = capture(() => api.pxBathFront(0, 0, 1));

const fixtures = {};
function samplePixels(commands, width, height) {
  const positions = new Map();
  // 覆盖每条原绘制指令的中心，比较最终合成颜色，而非只检查配置键名。
  for (const [x, y, w, h] of commands) {
    const px = Math.floor(x + w / 2), py = Math.floor(y + h / 2);
    if (px >= 0 && py >= 0 && px < width && py < height) positions.set(`${px},${py}`, [px, py]);
  }
  return [...positions.values()].map(([x, y]) => {
    let rgb = [0, 0, 0];
    for (const [rx, ry, rw, rh, r, g, b, alpha] of commands) {
      if (x + 0.5 < rx || y + 0.5 < ry || x + 0.5 >= rx + rw || y + 0.5 >= ry + rh) continue;
      rgb = [r, g, b].map((c, i) => c * alpha + rgb[i] * (1-alpha));
    }
    return [x, y, ...rgb.map(c => Math.round(c * 255))];
  });
}
function fixture(name, configure) {
  const state = api.reset(); api.pxResize(); configure(state);
  const commands = capture(() => api.pxDraw());
  const {width, height} = api.dimensions();
  fixtures[name] = {width, height, commands, samples: samplePixels(commands, width, height),
    state: JSON.parse(JSON.stringify(state)), visual: {bath: api.PX.bath, t: api.PX.t,
      face: api.PX.face, dir: api.PX.dir, hop: api.PX.hop, bob: api.PX.bob, annoy: api.PX.annoy}};
}
for (const key of Object.keys(api.THEMES)) {
  fixture(`theme_${key}`, () => api.theme(key));
  fixture(`night_${key}`, st => {api.theme(key); st.pets[0].asleep = true;});
  art.rooms[key] = {};
  for (const night of [false, true]) {
    api.reset(); api.theme(key); api.pxResize();
    art.rooms[key][night ? 'night' : 'day'] = capture(() => api.pxRoom({asleep: night}));
  }
}
for (const key of Object.keys(api.SPECIES)) fixture(`pet_${key}`, st => {api.theme('sakura'); st.pets = [api.makePet(key)];});
fixture('furniture_confirm', st => {
  api.theme('sakura'); st.placed.bed = {x: 0.5, y: 0.8, s: 1}; st.edit = true; st.sel = 'bed';
});
fixture('sleep_bed', st => {api.theme('sakura'); st.placed.bed = {x: 0.5, y: 0.8, s: 1}; st.pets[0].asleep = true;});
fixture('bath', () => {api.theme('sakura'); api.PX.bath = 1.5;});
fixture('wear_goose', st => {api.theme('sakura'); st.pets = [api.makePet('goose')]; st.pets[0].worn = {head: 'crown', neck: 'scarf', back: 'wings'};});
fixture('poop', st => {api.theme('sakura'); st.poops = [{lx: 0.35, ly: 0.7}];});
const defaultState = api.reset();
const outputs = {
  'catalog.json': {source_sha256: sourceHash, ...api.catalog, default_state: defaultState},
  'art.json': {source_sha256: sourceHash, ...art},
  'visual_fixtures.json': fixtures,
};
let mismatch = false;
for (const [name, data] of Object.entries(outputs)) {
  const destination = path.join(root, 'godot', 'data', name);
  const serialized = JSON.stringify(data) + '\n';
  if (process.argv.includes('--check')) {
    if (!fs.existsSync(destination) || fs.readFileSync(destination, 'utf8').replace(/\r\n/g, '\n') !== serialized) {
      console.error('生成数据与原 HTML 不一致：' + name); mismatch = true;
    }
  } else {
    fs.mkdirSync(path.dirname(destination), {recursive: true});
    fs.writeFileSync(destination, serialized);
  }
}
if (mismatch) process.exitCode = 1;
else console.log(`原版数据${process.argv.includes('--check') ? '校验' : '提取'}通过：${Object.keys(api.SPECIES).length} 种宠物、${Object.keys(api.PLACE).length} 件摆放物、${Object.keys(fixtures).length} 个视觉基准。`);
