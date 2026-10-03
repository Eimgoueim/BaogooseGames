import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

// 原 HTML 是行为基准；停用 DOM/存储/音频，仅运行其原有领域函数。
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = fs.readFileSync(path.join(root, '宠物养成游戏.html'), 'utf8').replace(/\r\n/g, '\n');
let script = source.match(/<script>([\s\S]*?)<\/script>/)[1];
script = script.replace('  boot();', `
  render = save = fx = feedFx = gainFx = petCry = playCry = pxDraw = closeAdopt = () => {};
  startBath = () => {}; toast = () => {}; openDialog = opts => { globalThis.confirm = opts.onConfirm; };
  showGacha = results => { globalThis.results = results; };
  globalThis.api = {makePet, defaultState, set: s => state = s, get: () => state,
    run: (action) => { const [key,arg] = action.split(':');
      switch(key) {
        case 'buy': buy(arg); break; case 'use': useItem(arg); break;
        case 'feedbest': feedBest(); break; case 'play': play(); break;
        case 'bath': bath(); break; case 'pet': petPet(); break;
        case 'sleep': toggleSleep(); break; case 'work': work(); break;
        case 'adoptpick': adopt(arg); break; case 'confirm': if(globalThis.confirm) globalThis.confirm(); break;
        case 'revive': revivePet(Number(arg)); break; case 'redeem': redeem(arg); break;
        case 'tick': for(let i=0;i<Number(arg||1);i++) tick(); break;
        case 'offline': applyOffline(); break; case 'pull': pull(Number(arg)); break;
        case 'cleanpoop': cleanPoop(Number(arg)); break; case 'reset': handle('reset'); break;
        case 'reset_confirm': if(globalThis.confirm) globalThis.confirm(); break;
      }
    }
  };`);
let now = 1_790_985_600_000, queue = [], cursor = 0;
class ClockDate extends Date {constructor(...args) {super(...(args.length ? args : [now]));} static now() {return now;}}
const math = Object.create(Math);
math.random = () => queue[cursor++] ?? 0.5;
const context = vm.createContext({Date: ClockDate, Math: math,
  document: {addEventListener() {}, getElementById(id) {return ['pointCount','coinCount','levelBadge'].includes(id)?{textContent:''}:null;}, body: {setAttribute() {}}, documentElement: {style: {setProperty() {}}}},
  window: {innerWidth:1120, innerHeight:960}, setTimeout: () => 0, clearTimeout() {}, localStorage: {setItem() {}, removeItem() {}},
});
vm.runInContext(script, context, {timeout:5000});
const api = context.api, fixtures = [];
const copy = value => JSON.parse(JSON.stringify(value));
function fixture(name, configure, operations, randoms = []) {
  now = 1_790_985_600_000; queue = randoms; cursor = 0;
  const state = api.defaultState(); configure(state); api.set(state); context.confirm = null; context.results = [];
  const input = copy(state);
  for(const operation of operations) api.run(operation);
  fixtures.push({name, state: input, now, randoms, operations, expected:copy(api.get()), results:copy(context.results)});
}
fixture('buy_food', s=>{}, ['buy:basic']);
fixture('buy_insufficient', s=>s.coins=0, ['buy:basic']);
fixture('buy_exclusive', s=>s.coins=1000, ['buy:oil']);
fixture('buy_wear', s=>s.coins=1000, ['buy:bow']);
fixture('buy_furniture', s=>s.coins=1000, ['buy:f_bed']);
fixture('use_food', s=>s.pets[0].hunger=10, ['use:basic']);
fixture('use_once_toy', s=>s.inv.ball=1, ['use:ball']);
fixture('use_ai_only_rejected', s=>s.inv.token=1, ['use:token']);
fixture('feed_best_favorite', s=>{s.pets[0].species='whale';s.inv={basic:1,rice:1};s.pets[0].hunger=10;}, ['feedbest']);
fixture('play', s=>s.hasToy=true, ['play']);
fixture('pet', s=>{}, ['pet']);
fixture('sleep_wake', s=>{}, ['sleep','sleep']);
fixture('sleep_full_recovery', s=>{s.pets[0].asleep=true;s.pets[0].energy=0;}, ['tick:20']);
fixture('work', s=>{}, ['work','work']);
fixture('bath', s=>{s.pets[0].clean=10;s.poops=[{lx:.5,ly:.7,t:now}];}, ['bath']);
fixture('adopt_initial_goose', s=>{}, ['adoptpick:goose']);
fixture('adopt_limited_locked', s=>{}, ['adoptpick:whale']);
fixture('adopt_full', s=>s.picked=true, ['adoptpick:cat']);
fixture('adopt_repeat', s=>{s.picked=true;s.lv=2;s.exp=7;s.pets[0].level=2;s.pets[0].exp=7;}, ['adoptpick:dragon','confirm']);
fixture('adopt_ten_full', s=>{s.picked=true;s.lv=10;while(s.pets.length<10){const p=api.makePet('cat');p.level=10;s.pets.push(p);}}, ['adoptpick:goose']);
fixture('tick_awake', s=>{}, ['tick:12']);
fixture('tick_sleep', s=>s.pets[0].asleep=true, ['tick:12']);
fixture('tick_level_up', s=>{s.exp=73;s.pets[0].exp=73;}, ['tick']);
fixture('shared_exp_rounding', s=>{s.lv=3;s.exp=142;s.pets[0].species='gpt';s.pets.push(api.makePet('cat'));}, ['tick']);
fixture('shared_legacy_level_fallback', s=>{s.lv=0;s.exp=5;s.pets[0].level=6;s.pets[0].exp=99;s.pets.push(Object.assign(api.makePet('cat'),{level:8,exp:2}));}, ['tick']);
fixture('affinity_unlock_memory', s=>{s.pets[0].affRank=8;s.pets[0].affinity=459.7;}, ['tick']);
fixture('affinity_unlock_gear', s=>{s.pets[0].affRank=14;s.pets[0].affinity=759.7;}, ['tick']);
fixture('tick_bench', s=>s.pets.push(api.makePet('cat')), ['tick:5']);
fixture('bench_critical_cry', s=>{const p=api.makePet('cat');p.hunger=11;p.cryAt=now-30000;s.pets.push(p);}, ['tick']);
fixture('death', s=>{s.pets[0].health=0;s.pets[0].sickT=179;s.pets[0].species='whale';s.collection=['whale'];}, ['tick']);
fixture('death_last_warning', s=>{s.pets[0].health=0;s.pets[0].sickT=179;}, ['tick']);
fixture('death_multiple_limited', s=>{const whale=s.pets[0];whale.species='whale';whale.health=0;whale.sickT=179;s.collection=['whale'];s.pets.push(api.makePet('cat'));s.active=1;}, ['tick']);
fixture('revive', s=>{s.lv=10;s.exp=4;s.coins=1000;s.grave=[{species:'whale',name:'小鲸',level:2,affRank:3,at:now}];s.shards.whale=10;}, ['revive:0']);
fixture('revive_level_too_low', s=>{s.coins=1000;s.grave=[{species:'cat',name:'咪咪',level:9,affRank:1,at:now}];}, ['revive:0']);
fixture('revive_coins_short', s=>{s.lv=10;s.coins=499;s.grave=[{species:'cat',name:'咪咪',level:10,affRank:1,at:now}];}, ['revive:0']);
fixture('revive_shards_short', s=>{s.lv=10;s.coins=500;s.grave=[{species:'whale',name:'小鲸',level:10,affRank:1,at:now}];}, ['revive:0']);
fixture('revive_replace_full_slot', s=>{s.lv=10;s.coins=500;while(s.pets.length<10)s.pets.push(api.makePet('cat'));s.grave=[{species:'cat',name:'咪咪',level:1,affRank:2,at:now}];}, ['revive:0']);
fixture('offline', s=>{s.lastTick=now-600000;s.pets.push(api.makePet('cat'));}, ['offline']);
fixture('clean_poop', s=>s.poops=[{lx:.5,ly:.7,t:now}], ['cleanpoop:0']);
fixture('reset_confirmed', s=>{s.coins=999;s.points=321;s.picked=true;}, ['reset','reset_confirm']);
const catalog = JSON.parse(fs.readFileSync(path.join(root,'godot/data/catalog.json'),'utf8'));
for(const key of Object.keys(catalog.POINT_SHOP)) fixture('redeem_'+key, s=>{s.points=10000;s.pointsTotal=10000;}, ['redeem:'+key]);
fixture('gacha_food', s=>{}, ['pull:1'], [.5,0]);
fixture('gacha_wear', s=>{}, ['pull:1'], [.5,91.5/97]);
fixture('gacha_deco', s=>{}, ['pull:1'], [.5,77/97]);
fixture('gacha_ten_wear_rewards', s=>{s.coins=1000;}, ['pull:10'], Array.from({length:20},(_,i)=>i%2===0?.5:91.5/97));
fixture('gacha_pet', s=>{}, ['pull:1'], [0,.8]);
fixture('gacha_duplicate', s=>s.collection=['whale'], ['pull:1'], [0,.8]);
fixture('gacha_small_spook', s=>s.pity=49, ['pull:1'], [0]);
fixture('gacha_big', s=>s.pity=99, ['pull:1'], []);
fixture('gacha_ten', s=>s.coins=1000, ['pull:10'], Array(40).fill(.5));
const data = JSON.stringify({source_sha256:crypto.createHash('sha256').update(source).digest('hex'),fixtures})+'\n';
const destination = path.join(root,'godot/data/gameplay_fixtures.json');
if(process.argv.includes('--check')) {
  if(!fs.existsSync(destination)||fs.readFileSync(destination,'utf8').replace(/\r\n/g,'\n')!==data) throw Error('行为夹具与原源码不匹配');
} else fs.writeFileSync(destination,data);
console.log('原版行为夹具：'+fixtures.length+' 组');
