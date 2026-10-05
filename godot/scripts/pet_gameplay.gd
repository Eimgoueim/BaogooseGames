extends RefCounted
## 原 HTML 宠物养成与经济层的纯状态实现。所有展示/存档副作用由事件交给调用方。

const MAX_PETS := 10
const TICK_MS := 5000
const POOP_MS := 300000
const POOP_WARN_MS := 9000
const POOP_MAX := 6
const DEATH_TICKS := 180
const REVIVE_COST := 500
const REVIVE_SHARDS := 10
const SHARDS_ON_DEATH := 10
const REVIVE_MIN_LV := 10

var state: Dictionary = {}
var catalog: Dictionary = {}
var now_ms: int = 0
var room_size: Vector2 = Vector2(128.0, 112.0)
var ground_end: float = 0.86
var bathing := false
var random: Callable
var _events: Array[Dictionary] = []
var _tick_accum: int = 0
var _poop_accum: int = 0
var _next_poop_cry_ms: int = 0
var _adopt_pending := ""

func setup(current: Dictionary, data: Dictionary) -> void:
	catalog = data
	state = current
	if state.is_empty(): state.merge(default_state(), true)
	if now_ms <= 0: now_ms = Time.get_unix_time_from_system() * 1000
	if not random.is_valid(): random = Callable(self, "_random_default")
	ensure_pet()

func inject_clock_and_random(timestamp_ms: int, random_callable: Callable = Callable()) -> void:
	now_ms = timestamp_ms
	if random_callable.is_valid(): random = random_callable

func _random_default() -> float:
	return randf()

func _rand() -> float:
	var v = random.call()
	return clampf(float(v), 0.0, 0.999999)

func _species() -> Dictionary: return catalog.get("SPECIES", {})
func _shop() -> Dictionary: return catalog.get("SHOP", {})
func _pet() -> Dictionary:
	ensure_pet()
	return state.pets[state.active]
func _sp(p: Dictionary) -> Dictionary: return _species().get(p.get("species", "dragon"), _species().get("dragon", {}))
func _clamp(v: float) -> float: return clampf(v, 0.0, 100.0)
func _numtext(value: Variant) -> String:
	var number := float(value)
	return str(int(number)) if is_equal_approx(number, float(int(number))) else str(value)
func _emit(type: String, fields: Dictionary = {}) -> void:
	var e := {"type": type}
	e.merge(fields, true)
	_events.append(e)
func _toast(s: String) -> void: _emit("toast", {"text": s})
func _changed(save_it := true) -> void:
	_emit("changed")
	if save_it: _emit("save")

func default_state() -> Dictionary:
	var p := make_pet("dragon")
	return {"ver":2,"pets":[p],"active":0,"coins":60,"points":0,"pointsTotal":0,
		"inv":{"basic":3},"hasToy":false,"seenItems":{},"wear":{},"placed":{},"furnOwn":{},
		"edit":false,"sel":"","theme":"sakura","accent":"","camYaw":0,"camZoom":1,"best":{},
		"lv":1,"exp":0,
		"decos":{},"collection":[],"picked":false,"bgm":true,"poops":[],"grave":[],"shards":{},
		"banner":"whale","pity":0,"title":"","decor":false,"memoUnlocked":false,"gearGiven":false,
		"pulls":0,"lastTick":now_ms if now_ms > 0 else Time.get_unix_time_from_system() * 1000,"workReady":0}

func make_pet(key: String) -> Dictionary:
	var species: Dictionary = _species().get(key, _species().get("dragon", {}))
	var base: Dictionary = species.get("base", {})
	var names := {"dragon":"团子","hoshino":"星野","cat":"咪咪","whale":"大肥鱼","gpt":"GPT","claude":"Claude","gemini":"Gemini"}
	return {"species":species.get("key", "dragon"),"name":names.get(species.get("key", "dragon"), "宝宝"),
		"level":1,"exp":0,"hunger":base.get("hunger",75),"mood":base.get("mood",75),"clean":base.get("clean",75),
		"energy":base.get("energy",80),"health":base.get("health",100),"affRank":1,"affinity":0,
		"asleep":false,"ageTicks":0,"born":now_ms if now_ms > 0 else Time.get_unix_time_from_system()*1000,
		"worn":{},"poopNext":(now_ms if now_ms > 0 else Time.get_unix_time_from_system()*1000)+POOP_MS,"poopWarn":false}

func ensure_pet() -> Dictionary:
	if not state.get("pets") or state.pets.is_empty():
		state.pets = [make_pet("dragon")]
		state.active = 0
	state.active = clampi(int(state.get("active", 0)), 0, state.pets.size()-1)
	return state.pets[state.active]

func _level_need(level: int) -> int: return 40 + level * 35
func _aff_need(rank: int) -> int: return 60 + rank * 50
func player_level() -> int:
	var level := int(state.get("lv", 0))
	if level < 1:
		level = 1
		for pet in state.get("pets", []): level = maxi(level, int(pet.get("level", 0)))
	return maxi(1, level)
func sync_levels() -> void:
	var level := player_level()
	state.lv = level
	state.exp = maxi(0, int(state.get("exp", 0)))
	for pet in state.get("pets", []): pet.level = level; pet.exp = state.exp
func _best_level() -> int:
	return player_level()
func _slots() -> int: return mini(MAX_PETS, maxi(1, _best_level()))
func _fav(key: String, p: Dictionary) -> bool: return key in _sp(p).get("perks", {}).get("favItems", [])

func add_exp(n: float) -> void:
	if n == 0: return
	var p := _pet()
	var perks: Dictionary = _sp(p).get("perks", {})
	var gain := maxi(1, roundi(n * float(perks.get("expMul", 1))))
	var stages: Array = _sp(p).get("stages", [])
	var old_stage := ""
	for s in stages:
		if p.level >= s.min: old_stage = s.name
	sync_levels()
	var old_level := player_level()
	state.exp += gain
	var leveled := false
	while state.exp >= _level_need(player_level()):
		state.exp -= _level_need(player_level())
		state.lv = player_level() + 1
		state.coins += 50
		p.mood = _clamp(p.mood + 10)
		leveled = true
	sync_levels()
	if leveled:
		var stage := ""
		for s in stages:
			if p.level >= s.min: stage = s.name
		if stage != old_stage: _toast("✨ 成长啦！玩家等级 Lv." + _numtext(player_level()) + " → " + p.name + " 也变成「" + stage + "」")
		else: _toast("🎉 玩家等级 Lv." + _numtext(old_level) + " → Lv." + _numtext(player_level()) + "！所有宠物一起升级（信用点 +50 · 栏位 " + _numtext(_slots()) + "/10）")

func add_affinity(n: float) -> void:
	if n == 0: return
	var p := _pet()
	p.affinity += n
	var ranked := false
	while p.affinity >= _aff_need(p.affRank):
		p.affinity -= _aff_need(p.affRank)
		p.affRank += 1
		var bonus: int = 10 * p.affRank
		state.coins += bonus
		ranked = true
		_toast("💗 " + p.name + " 羁绊提升！Lv." + _numtext(p.affRank) + "（信用点 +" + _numtext(bonus) + "）")
		if p.affRank == 9 and not state.memoUnlocked:
			state.memoUnlocked = true
			_toast("🌌 羁绊 Lv.9：解锁「记忆大厅」")
		if p.affRank == 15 and not state.gearGiven:
			state.gearGiven = true
			state.inv.pillow = int(state.inv.get("pillow",0))+1
			_toast("🎁 羁绊 Lv.15：获得专属装备「随地入梦枕」")
	if ranked: p.mood = _clamp(p.mood + 5)

func gain_points(n: int, credits := 0, exp := 0) -> void:
	state.points += n
	state.pointsTotal += n
	if credits: state.coins += credits
	if exp: add_exp(exp)

func drain_events() -> Array[Dictionary]:
	var result := _events.duplicate(true)
	_events.clear()
	return result

func _effects(effects: Dictionary, mood_mul := 1.0, hunger_mul := 1.0) -> void:
	var p := _pet()
	for k in effects:
		if p.has(k):
			var v := float(effects[k])
			if k == "mood": v *= mood_mul
			if k == "hunger": v *= hunger_mul
			p[k] = _clamp(float(p[k])+v)

func _use(key: String) -> void:
	var item: Dictionary = _shop().get(key, {})
	var p := _pet()
	if item.is_empty(): return
	if item.get("only", "") != "" and item.only != p.species:
		_toast("这是" + _species()[item.only].name + "专属道具"); return
	if item.get("onlyKind", "") == "ai" and not _sp(p).get("ai", false):
		_toast("这是 AI 型宠物专用道具（" + _ai_names() + "）"); return
	if p.asleep: _toast("😴 " + p.name + " 睡着了，先叫醒它"); return
	if int(state.inv.get(key,0)) <= 0: _toast("背包里没有" + item.name + "了"); return
	if item.has("wear") or item.has("furn") or item.has("deco"):
		# 这类不是喂给宠物用的：不要白消耗，直接告诉玩家去哪里用
		if item.has("wear"):
			_toast("🎀 「" + item.name + "」是佩饰：去「🎀 佩饰」页面点它给宠物戴上")
		elif item.has("furn"):
			_toast("🛋️ 「" + item.name + "」是家具：去「🛋️ 房间」页面摆放")
		else:
			_toast("🧸 「" + item.name + "」是装饰：去「🛋️ 房间」页面摆放")
		return
	var fav := _fav(key,p)
	var perks: Dictionary = _sp(p).get("perks", {})
	var mm := float(perks.get("sweetMood",1.4)) if fav else 1.0
	var hm := float(perks.get("foodMul",1)) if item.get("effects",{}).has("hunger") else 1.0
	state.inv[key] -= 1
	state.seenItems[key] = 1
	_effects(item.get("effects",{}),mm,hm)
	if item.get("once",false): state.hasToy = true
	add_exp(item.get("exp",0))
	add_affinity(item.get("favAff",4) if fav else 2)
	var gains: Array[String] = []
	var ef: Dictionary = item.get("effects",{})
	for pair in [["hunger","🍖",hm],["mood","😊",mm],["energy","⚡",1.0],["clean","🫧",1.0],["health","❤️",1.0]]:
		if ef.has(pair[0]): gains.append(pair[1]+"+"+str(roundi(float(ef[pair[0]])*pair[2])))
	_emit("feed", {"emoji":item.get("emoji",""),"text":" ".join(gains)})
	_toast(item.get("emoji","")+" "+p.name+" 使用了 "+item.name+("（它很喜欢！心情额外提升）" if fav else ""))
	_changed()

func _ai_names() -> String:
	var names: Array[String] = []
	for k in _species():
		if _species()[k].get("ai",false): names.append(_species()[k].name)
	return " / ".join(names)

func _buy(key: String) -> void:
	var item: Dictionary = _shop().get(key,{})
	if item.is_empty(): return
	var p := _pet()
	if item.get("only","") != "" and item.only != p.species: _toast("这是"+_species()[item.only].name+"专属道具，换个宠物才能买"); return
	if item.get("onlyKind","") == "ai" and not _sp(p).get("ai",false): _toast("这是 AI 型宠物专用道具（"+_ai_names()+"），换个 AI 型宠物才能买"); return
	var price := int(item.get("price",0))
	if item.get("furn",false):
		var fk: String = item.get("furnKey","")
		if state.get("furnOwn",{}).get(fk,false): _toast("已经拥有"+item.name+"啦"); return
		if state.coins < price: _toast("💰 信用点不够，去打打工或玩游戏赚点吧"); return
		state.coins -= price; state.furnOwn[fk]=1; state.seenItems[key]=1
		var place: Dictionary = catalog.get("PLACE", {}).get(fk, {})
		var def: Dictionary = place.get("def", {"x":64,"y":96,"s":1})
		state.placed[fk] = state.placed.get(fk, {"x":def.get("x",64),"y":def.get("y",96),"s":def.get("s",1)})
		state.edit=true; state.sel=fk
		_toast("🛋️ 买到了 "+item.name+"，已放进房间，拖动摆好位置吧")
	elif item.get("wear",false):
		if state.wear.get(key,false): _toast("已经拥有"+item.name+"啦"); return
		if state.coins < price: _toast("💰 信用点不够，去打打工或玩游戏赚点吧"); return
		state.coins-=price; state.wear[key]=1; state.seenItems[key]=1
		_toast("🎀 买到了 "+item.name+"，去「🎀 佩饰」给它戴上")
	else:
		if item.get("once",false) and state.hasToy: _toast("已经拥有"+item.name+"啦"); return
		if state.coins < price: _toast("💰 信用点不够，去打工或玩小游戏赚点吧"); return
		state.coins-=price; state.inv[key]=int(state.inv.get(key,0))+1; state.seenItems[key]=1
		_toast("🛒 买到了 "+item.name)
	_changed()

func _play() -> void:
	var p := _pet(); var perks: Dictionary = _sp(p).get("perks",{})
	if p.asleep: _toast("😴 "+p.name+" 在睡觉呢"); return
	if p.energy < 10: _toast("⚡ 精力不够，先让它休息一下吧"); return
	var mg := roundi((26 if state.hasToy else 18)*float(perks.get("playMood",1)))
	var eg := roundi((20 if state.hasToy else 12)*float(perks.get("playExp",1)))
	p.energy=_clamp(p.energy-10); p.hunger=_clamp(p.hunger-5); _effects({"mood":mg}); add_exp(eg); add_affinity(4)
	var msg: String = "🎾 "+p.name+" 玩得好开心！"
	if _rand()<0.25: state.coins+=6; msg="🎾 玩得开心，还捡到 💰6！"
	_emit("effect",{"kind":"💖"}); _toast(msg); _changed()

func _bath() -> void:
	var p := _pet(); var pk: Dictionary = _sp(p).get("perks",{})
	if p.asleep: _toast("😴 睡着了不能洗澡哦"); return
	var due := int(p.get("poopNext",0))>0 and now_ms > int(p.poopNext)-POOP_WARN_MS
	if state.get("poops",[]).is_empty() and not due and p.clean>=98: _toast("🫧 已经很干净啦"); return
	var msg := ""
	if not state.poops.is_empty():
		msg="清理了 "+_numtext(state.poops.size())+" 坨，"; state.poops.clear(); p.clean=_clamp(p.clean+6); p.mood=_clamp(p.mood+4)
	if due:
		p.poopNext=now_ms+POOP_MS; p.poopWarn=false; msg+="又帮它顺利拉出来了，"; p.mood=_clamp(p.mood+2)
	p.clean=_clamp(p.clean+48*float(pk.get("bathGain",1))); p.mood=_clamp(p.mood-4); p.hunger=_clamp(p.hunger-2)
	add_exp(8); add_affinity(2); _emit("bath"); _emit("effect",{"kind":"🫧"})
	_toast("🛁 "+msg+p.name+" 洗得香喷喷，清洁度大涨！"); _changed()

func _pet_action() -> void:
	var p:=_pet()
	var lines: Dictionary={"dragon":["团子眯起眼睛，把脑袋往你手心里顶","团子的尾巴轻轻拍了两下地板"],"hoshino":["星野「嗯……」了一声，像大叔一样把头枕在你的手上","星野半睁着眼蹭了蹭，好像打算就这么睡过去"],"cat":["咪咪发出咕噜咕噜的声音","咪咪翻过身来露出肚皮——这是最高信任"],"whale":["大肥鱼整只软软地瘫在你手上，体重感人","大肥鱼开心地用尾鳍拍了拍地面"],"gpt":["GPT 安静地把头低下来，龙角轻轻碰到你的手","GPT 的银白翅膀抖了一下，发出细微的嗡鸣"]}
	var choices: Array = lines.get(p.species,lines.dragon)
	var line: String=choices[int(_rand()*choices.size())]
	_emit("effect",{"kind":"💗"})
	if p.asleep: add_affinity(1); _toast("💤 "+line+"（睡梦中，羁绊 +1）")
	else:
		var gain:=8 if p.mood<60 else 4
		gain=roundi(gain*float(_sp(p).get("perks",{}).get("petMood",1)))
		p.mood=_clamp(p.mood+gain); add_exp(1); add_affinity(2)
		var msg: String="🤚 "+line+"（心情 +"+str(gain)+"）"
		if _rand()<0.06: state.coins+=3; msg+="，还在毛里发现 💰3"
		_toast(msg)
	_changed()

func _sleep() -> void:
	var p:=_pet(); p.asleep=not p.asleep
	if p.asleep: _toast("💤 "+p.name+(" 爬上小床，钻进被窝睡着了…" if state.get("placed",{}).has("bed") else " 趴进被窝睡着了…（摆放一张床就能睡床上）"))
	else: _toast("☀️ "+p.name+" 醒来了")
	_changed()

func _work() -> void:
	var p:=_pet()
	if p.asleep: _toast("😴 "+p.name+" 在睡觉"); return
	var left=int(state.get("workReady",0))-now_ms
	if left>0: _toast("💼 休息一下，"+_numtext(ceili(left/1000.0))+" 秒后再打工"); return
	if p.energy<20: _toast("⚡ 精力不足，没法打工"); return
	var pay:=12+int(_rand()*15); state.coins+=pay; p.energy=_clamp(p.energy-20); p.mood=_clamp(p.mood-8)
	state.workReady=now_ms+60000; add_exp(15); add_affinity(2); _emit("effect",{"kind":"💰"}); _toast("💼 打工结束，赚到 💰"+_numtext(pay)); _changed()

func _adopt(key: String) -> void:
	if not _species().has(key): return
	var sp: Dictionary=_species()[key]
	if sp.get("limited",false) and key not in state.collection: _toast("🔒 「"+sp.name+"」是抽卡限定宠物，去「🎰 抽卡」试试手气"); return
	if not state.picked:
		state.picked=true; _do_adopt(key,0); _toast("🎉 初始宠物选定！升级会解锁更多栏位（每级 +1 栏位、+50 信用点）"); return
	var unlocked:=_slots()
	if state.pets.size()>=unlocked:
		if unlocked>=MAX_PETS: _toast("🐾 已经有 10 只宠物了，养不过来啦")
		else: _toast("🔒 宠物栏位满了（"+_numtext(state.pets.size())+"/"+_numtext(unlocked)+"）· 升到 Lv."+_numtext(unlocked+1)+" 解锁新栏位")
		return
	if key in state.pets.map(func(q): return q.species):
		_adopt_pending=key
		_emit("dialog",{"opts":{"title":"重复领养确认","body":"已经有「"+sp.name+"」了，仍要再领养一只吗？","confirmText":"确认领养"},"confirm_action":"adopt_confirm"})
		return
	_do_adopt(key,-1)

func _do_adopt(key: String, slot: int) -> void:
	var p:=make_pet(key); p.level=player_level(); p.exp=maxi(0,int(state.get("exp",0))); var base: String=p.name; var n:=2
	while state.pets.any(func(q): return q.name==p.name and state.pets.find(q)!=slot): p.name=base+str(n); n+=1
	if slot>=0 and slot<state.pets.size(): state.pets[slot]=p
	else: state.pets.append(p)
	state.active=slot if slot>=0 else state.pets.size()-1
	_toast("🐾 "+p.name+"（"+_species()[key].name+"）加入了！"); _emit("adopt_close"); _changed()

func _revive(index: int) -> void:
	if index<0 or index>=state.grave.size(): return
	var g: Dictionary=state.grave[index]
	if player_level()<REVIVE_MIN_LV: _toast("🪦 玩家等级 Lv."+_numtext(player_level())+"，需要到 Lv.10 才能复活（提升等级后来看看）"); return
	var sp: Dictionary=_species().get(g.species,_species().dragon); var need:=REVIVE_SHARDS if sp.get("limited",false) else 0
	if state.coins<REVIVE_COST: _toast("💰 复活需要 500 信用点（不够）"); return
	if int(state.shards.get(g.species,0))<need: _toast("🧩 还缺碎片："+sp.name+" 需要 10 个（当前 "+str(state.shards.get(g.species,0))+"）"); return
	state.coins-=REVIVE_COST
	if need: state.shards[g.species]-=need
	var p:=make_pet(g.species); p.name=g.name; p.level=player_level(); p.hunger=55;p.mood=50;p.clean=55;p.energy=60;p.health=55;p.affRank=maxi(1,int(g.affRank))
	if state.pets.is_empty(): state.pets.append(p)
	elif state.pets.size()>=_slots(): state.pets[state.active]=p
	else: state.pets.append(p)
	state.grave.remove_at(index); state.active=state.pets.find(p); p.poopNext=now_ms+POOP_MS;p.poopWarn=false
	_toast("✨ "+p.name+" 复活了！欢迎回来（Lv."+_numtext(p.level)+"）"); _changed()

func _redeem(key: String) -> void:
	var it: Dictionary=catalog.get("POINT_SHOP",{}).get(key,{})
	if it.is_empty(): return
	if it.get("once",false) and state.get(it.get("flag",""),false): _toast("这个已经兑换过啦"); return
	if state.points<int(it.cost): _toast("⭐ 积分不够，去「🎮 宠物地牢」打一局吧"); return
	state.points-=int(it.cost)
	match key:
		"credits": state.coins+=50
		"drink": _pet().energy=_clamp(_pet().energy+50)
		"pyroxene": state.inv.pyroxene=int(state.inv.get("pyroxene",0))+1
		"title": state.title="对策委员会顾问"
		"decor": state.decor=true
	_toast(it.emoji+" 兑换成功："+it.name); _changed()

func dispatch(action: String) -> Array[Dictionary]:
	_events=[]
	var parts := action.split(":", false, 1)
	var op: String = parts[0]
	var arg: Variant = parts[1] if parts.size() > 1 else ""
	match op:
		"buy": _buy(str(arg))
		"use": _use(str(arg))
		"feedbest": _feed_best()
		"play": _play()
		"bath": _bath()
		"pet": _pet_action()
		"sleep": _sleep()
		"work": _work()
		"adoptpick": _adopt(str(arg))
		"adopt_confirm":
			if _adopt_pending!="": _do_adopt(_adopt_pending,-1); _adopt_pending=""
		"adopt_cancel": _adopt_pending=""
		"revive": _revive(int(arg))
		"redeem": _redeem(str(arg))
		"cleanpoop": _clean_poop(int(arg))
		"reset_confirm": state.clear(); state.merge(default_state(),true); _changed()
		"reset": _emit("dialog",{"opts":{"title":"重新开始","body":"确定要清空全部进度吗？（宠物、信用点、积分、图鉴都会重置）","confirmText":"确认重开"},"confirm_action":"reset_confirm"})
	return _events

func _clean_poop(index: int) -> void:
	if index<0 or index>=state.poops.size(): return
	state.poops.remove_at(index)
	var p:=_pet();p.clean=_clamp(p.clean+6);p.mood=_clamp(p.mood+4)
	gain_points(2,0,1);_emit("effect",{"kind":"🧹"});_toast("🧹 清理干净啦（清洁 +6 · 心情 +4 · 积分 +2）");_changed()

func _feed_best() -> void:
	var p:=_pet()
	if p.asleep: _toast("😴 它睡着了，先叫醒它再喂"); return
	var candidates: Array[String]=[]
	for k in state.inv:
		var it: Dictionary=_shop().get(k,{})
		if int(state.inv[k])>0 and it.has("effects") and int(it.effects.get("hunger",0))!=0 and not it.get("wear",false) and not it.get("furn",false) and not it.get("deco",false) and (not it.get("only","") or it.only==p.species) and (it.get("onlyKind","")!="ai" or _sp(p).get("ai",false)): candidates.append(k)
	if candidates.is_empty(): _toast("🎒 背包里没有食物了"); return
	candidates.sort_custom(func(a,b):
		var fa:=_fav(a,p); var fb:=_fav(b,p)
		if fa!=fb: return fa
		var cheap:=100 if p.hunger>70 else 0
		return int(_shop()[b].effects.hunger)-cheap > int(_shop()[a].effects.hunger)-cheap
	)
	_use(candidates[0])

func _step_pet(p: Dictionary, mode: String) -> bool:
	var sp:=_sp(p); var decay: Dictionary=sp.get("decay",{}); var perks: Dictionary=sp.get("perks",{})
	var k:=1.0 if mode=="active" else 0.5; var woke:=false
	if p.asleep:
		var bed:=1.5 if state.get("placed",{}).has("bed") else 1.0
		p.energy+=6*float(perks.get("sleepEnergy",1))*k*bed
		if perks.get("sleepMood",0): p.mood+=float(perks.sleepMood)
		p.hunger-=0.15*k;p.mood-=0.08*k;p.clean-=0.10*k;p.health+=1.4*k if p.hunger>25 else -1.0*k
		if p.energy>=100: p.energy=100;p.asleep=false;woke=true
	else:
		p.hunger-=0.30*float(decay.get("hunger",1))*k;p.mood-=0.28*float(decay.get("mood",1))*k;p.clean-=0.24*float(decay.get("clean",1))*k
		if mode=="active": p.energy-=0.32*float(decay.get("energy",1))
		else: p.energy+=0.15
		if p.hunger<20:p.health-=1*k
		if p.clean<20:p.health-=0.7*k
		if p.mood<20:p.health-=0.5*k
		if p.hunger>=40 and p.clean>=40 and p.mood>=40:p.health+=0.8
	for k2 in ["hunger","mood","clean","energy","health"]: p[k2]=_clamp(p[k2])
	p.ageTicks=int(p.get("ageTicks",0))+1
	return woke

func _poop_fix(p: Dictionary) -> void:
	if int(p.get("poopNext",0))<=0 or now_ms-int(p.poopNext)>POOP_MS:
		p.poopNext=now_ms+POOP_MS
		return
	if p.get("asleep",false): return
	var left:=int(p.poopNext)-now_ms
	if left<=POOP_WARN_MS and not p.get("poopWarn",false):
		p.poopWarn=true;_emit("cry",{"species":p.species})
	if left<=0:
		var i:=int(_rand()*8);var a:=float(i)/7.0
		state.poops.append({"lx":0.08+0.84*a,"ly":0.72+_rand()*0.18,"t":now_ms})
		if state.poops.size()>POOP_MAX:state.poops.pop_front()
		p.poopNext=now_ms+POOP_MS;p.poopWarn=false;p.clean=_clamp(p.clean-18);p.mood=_clamp(p.mood-6);p.hunger=_clamp(p.hunger-5)
		_emit("effect",{"kind":"💩"});_toast("💩 "+p.name+" 拉了一坨（饱食 -5）…点它就能清理（或用 🛁 清洁键）")

func _kill(p: Dictionary, reason: String) -> void:
	if state.pets.size()<=1:return
	var idx: int=state.pets.find(p); if idx<0:return
	var sp:=_sp(p); state.grave.append({"species":p.species,"name":p.name,"level":p.level,"affRank":p.affRank,"at":now_ms})
	if state.grave.size()>12:state.grave.pop_front()
	state.pets.remove_at(idx);state.active=clampi(state.active,0,state.pets.size()-1)
	if sp.get("limited",false):state.shards[p.species]=int(state.shards.get(p.species,0))+SHARDS_ON_DEATH
	_toast("💀 "+p.name+" "+reason+"…已离世"+("（变成 10 个碎片）" if sp.get("limited",false) else "")+"，去 🐾 领养面板看看")
	if state.grave.any(func(g):return int(g.level)>=REVIVE_MIN_LV):_toast("✨ 到过 Lv.10 的伙伴可以在领养面板复活")

func tick() -> Array[Dictionary]:
	_events=[]
	var p:=_pet()
	if _step_pet(p,"active"): _toast("☀️ "+p.name+" 睡饱啦，精神满满！")
	add_exp(2); add_affinity(0.4 if p.asleep else 0.3)
	for i in range(state.pets.size()):
		var q: Dictionary=state.pets[i]
		if i!=state.active:_step_pet(q,"bench")
		if int(q.get("poopNext",0))<=0 or now_ms-int(q.poopNext)>POOP_MS:q.poopNext=now_ms+POOP_MS
		var bad: bool=q.health<=5 or q.hunger<15 or q.clean<12 or q.mood<10
		q.sickT=int(q.get("sickT",0))+1 if bad else 0
		var critical: bool = q.health<=0 or q.hunger<12 or int(q.get("sickT",0))>0
		if i!=state.active and critical and now_ms-int(q.get("cryAt",0))>=30000:
			q.cryAt=now_ms;_emit("cry",{"species":q.species,"text":catalog.get("CRIES",{}).get(q.species,"呜…")});_toast("😿 "+q.name+" 在家饿得直叫…（点上方头像切过去看看）")
	for q in state.pets.duplicate():
		if int(q.get("sickT",0))>=DEATH_TICKS:
			if state.pets.size()>1:_kill(q,"生病太久没人管")
			elif not q.get("warnedDead",false):q.warnedDead=true;_toast("🚨 "+q.name+" 已经撑不住了！喂点吃的、洗个澡或让它睡觉，再不管会有危险")
	if not state.poops.is_empty():p.clean=_clamp(p.clean-0.6);p.mood=_clamp(p.mood-0.3)
	_changed();return _events

func _offline_pet(p: Dictionary, ticks: int, mode: String) -> void:
	var k:=1.0 if mode=="active" else 0.5; var perks: Dictionary=_sp(p).get("perks",{})
	p.hunger-=minf(ticks*0.30,45)*k;p.mood-=minf(ticks*0.28,40)*k;p.clean-=minf(ticks*0.24,38)*k
	if p.asleep:
		p.energy+=minf(ticks*6*float(perks.get("sleepEnergy",1)),100)*k
		if p.energy>=100:p.energy=100;p.asleep=false
	elif mode=="active":p.energy-=minf(ticks*0.32,25)
	else:p.energy+=minf(ticks*0.15,40)
	for key in ["hunger","mood","clean","energy","health"]:p[key]=_clamp(p[key])
	p.ageTicks=int(p.get("ageTicks",0))+mini(ticks,2000)

func apply_offline() -> Array[Dictionary]:
	_events=[]
	var ticks:=floori(float(now_ms-int(state.get("lastTick",now_ms)))/TICK_MS)
	if ticks<1:return _events
	for i in range(state.pets.size()):_offline_pet(state.pets[i],ticks,"active" if i==state.active else "bench")
	var m:=floori(ticks*TICK_MS/60000.0); var duration:=str(m)+" 分钟" if m<60 else str(floori(m/60.0))+" 小时"+(str(m%60)+" 分" if m%60 else "")
	_toast("你离开了 "+duration+"，"+_pet().name+" 有点想你了～");_changed();return _events

func advance_time(delta_ms: int) -> Array[Dictionary]:
	_events=[]
	var combined: Array[Dictionary]=[]
	var remaining := maxi(0, delta_ms)
	var to_tick := TICK_MS - _tick_accum
	# 时间戳落在真实跨过的tick边界。例如已累计4900ms时再推进200ms，tick位于+100ms。
	while remaining >= to_tick:
		now_ms += to_tick
		remaining -= to_tick
		_tick_accum = 0
		for e in tick(): combined.append(e)
		if not state.pets.is_empty():
			_events=[]
			_simulate_poop(_pet())
			for e in _events: combined.append(e)
		to_tick = TICK_MS
	now_ms += remaining
	_tick_accum += remaining
	# 实时排泄只作用于出战宠物；帧间隔内没有tick时也继续计时。
	if not state.pets.is_empty():
		_events=[]
		_simulate_poop(_pet())
		for e in _events: combined.append(e)
	_events=combined
	return _events

func _simulate_poop(p: Dictionary) -> void:
	if bathing:
		p.poopWarn=false
		return
	if p.asleep:return
	if int(p.get("poopNext",0))<=0:p.poopNext=now_ms+POOP_MS
	var left:=int(p.poopNext)-now_ms
	p.poopWarn=left<=POOP_WARN_MS
	if p.poopWarn:
		if _next_poop_cry_ms<=0:_next_poop_cry_ms=now_ms
		if now_ms>=_next_poop_cry_ms:
			_emit("cry",{"species":p.species,"text":catalog.get("CRIES",{}).get(p.species,"呜…")})
			_next_poop_cry_ms=now_ms+1500
	else:_next_poop_cry_ms=0
	if left<=0:
		var width := maxf(1.0, room_size.x)
		var height := maxf(1.0, room_size.y)
		var fx := clampf(float(p.get("lx", 0.5)), 0.08, 0.92)
		var fy := clampf(float(p.get("ly", 0.8)), 0.14, ground_end)
		var poop_x := clampf(roundf(fx * width) / width, 0.08, 0.92)
		var poop_y := clampf(roundf(fy * height) / height, 0.14, ground_end)
		state.poops.append({"lx":poop_x,"ly":poop_y,"t":now_ms})
		if state.poops.size()>POOP_MAX:state.poops.pop_front()
		p.poopNext=now_ms+POOP_MS;p.poopWarn=false;p.clean=_clamp(p.clean-18);p.mood=_clamp(p.mood-6);p.hunger=_clamp(p.hunger-5)
		_emit("effect",{"kind":"💩"});_toast("💩 "+p.name+" 拉了一坨（饱食 -5）…点它就能清理（或用 🛁 清洁键）")

func process(timestamp_ms: int) -> Array[Dictionary]:
	return advance_time(maxi(0,timestamp_ms-now_ms))
