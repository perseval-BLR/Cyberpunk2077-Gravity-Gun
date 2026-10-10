-- Gravity Gun (Half-Life 2) for Cyberpunk 2077 v1.0.0 - fan-made, non-commercial. See README / CREDITS.
--
-- The gun: Items.GravGun (TweakXL r6/tweaks/gravgun.yaml; an Igla underneath with the HL2 model on its receiver,
-- gravgun.archive), given a few seconds after a load if V has none. Its own shooting and aiming are switched off
-- (SemiAuto/... and AimingState decisions return false while it is in hands). Sounds: Audioware r6/audioware/gravgun.
--
-- Behaviour follows HL2's weapon_physcannon.cpp (Source SDK 2013; inches -> metres, 1 in = 0.0254 m):
--   right mouse HELD   - pull: the object under the crosshair (in a cone) is pulled towards the gun by a force
--                        (physcannon_pullforce 4000 per 0.1 s; under 50 kg scaled by (m + 0.5) / 50), so it starts
--                        slowly and speeds up, heavy things slowly; once it is close it is grabbed
--                        (HL2: a quarter of the trace length). Letting go of the button stops pulling.
--   right mouse again  - drop.
--   held               - kept at eye level in front (24 in + player radius + half the object), following the aim
--                        (pitch clamped to +-75 deg) and turning with V (its yaw relative to V's stays); the shadow
--                        controller of HL2 is a fast damped follow (up to 1000 in/s).
--   left mouse, held   - launch: velocity ADDED along the aim, 1500 in/s up to 100 kg, spline down to 700 in/s at
--                        600 kg and more (Pickup_DefaultPhysGunLaunchVelocity), plus a spin.
--   left mouse, empty  - punt: impulse 15000 + min(m, 250) * 600 (vehicles 625) kg in/s; a downward aim is partly
--                        turned upwards (z * -0.65).
-- HL2's normal gun lifts up to 250 kg and no living NPCs; people and cars here follow its Citadel (mega) gun:
-- range 850 in, pull 8000 - people become ragdolls on release. NPCs and cars are carried kinematically (each frame
-- the gun puts them on its own path: impulse control of a ragdoll or a car did not work, runs 1-4); physics takes
-- over on release (ragdoll impulse; a thrown car flies its own ballistic path until it hits something).
-- Keyboard bindings (CET -> Bindings) do the same with any weapon. Log: gravgun/log.txt.

local GUN = "Items.GravGun"
local IN = 0.0254   -- HL2 inch in metres

local CFG = {
    range = {prop = 250 * IN, npc = 850 * IN, vehicle = 850 * IN},          -- physcannon_(mega_)tracelength
    grab_range = 850 * IN,   -- the search reach (the per-kind range is checked after)
    pull_force = {prop = 4000, npc = 8000, vehicle = 8000},                 -- physcannon_(mega_)pullforce
    pull_period = 0.1,       -- HL2 applies the pull impulse every 0.1 s while the button is held
    pull_max_speed = 12.0,   -- m/s (HL2 has no cap but air drag; kinematic objects need one)
    -- grabbed when this close (HL2: a quarter of the trace length for the normal gun; for carried people and cars
    -- the hold distance + 1 m, so the pull - the part the owner asked to be slow first - covers the approach)
    attach = {prop = 250 * IN * 0.25},
    attach_extra = 1.0,
    player_radius = 0.57,    -- HL2 player bbox: 16 x 16 in half-extents -> Length2D 22.6 in
    half_size = {prop = 0.3, npc = 0.35, vehicle = 2.3},   -- half the object along the aim (HL2 CollideGetExtent)
    centre_up = {prop = 0.0, npc = 1.0, vehicle = 0.8},    -- NPC/car position is the feet / floor: centre above
    follow_time = {prop = 0.12, npc = 0.12, vehicle = 0.3},   -- s: lag behind the point (HL2 shadow control); a car
                             -- wobbled up to 1 m at 0.12 (run 6: the game keeps simulating it between our moves)
    -- people: HL2's 1500 in/s launch and 15000+600m punt are for props; on a person they were too much (run 6:
    -- launched at 38 m/s, owner earlier 'very strong') - scaled
    -- owner (run 6.1): 'less for people, a bit more for big things': per-kind multipliers on HL2's launch and punt
    -- owner (run 6.2): 'people still fly far from a push' - 0.2; their impulse also over a smaller part of the body
    -- owner (run 6.6): 'push big objects about twice as hard, send people ~20% less'
    -- owner (run 6.9): 'the push needs to be about twice as strong' - everything x2 (people punt 4.9 -> 9.8 m/s,
    -- launch 9.1 -> 18.3 m/s)
    -- owner (run 6.10): 'almost there - people ~20% more, cars ~30% less' (people punt 11.8, launch 22.0 m/s)
    -- owner (run 6.15): 'the push and the launch after a grab ~30% stronger, for people and for cars'
    force_scale = {prop = 2.0, npc = 0.749, vehicle = 5.10},
    -- the launch of what is held has its own scale (run 6.11, log: a held 1500 kg car left at 69.7 m/s with the punt's
    -- 3.92 - owner: 'cars fly off far too hard'; people 'a bit more'): cars ~24 m/s, people 21.9 -> ~25 m/s
    launch_scale = {prop = 2.0, npc = 0.858, vehicle = 1.755},
    -- a person is pulled and held by ONE point - the body part under the crosshair - like a lifeless ragdoll on a
    -- string (run 6.6: impulses over the whole hips area every frame + a 'living' ragdoll re-triggered every second
    -- twisted and stretched the body): small impulse radius, a velocity controller on that point (no mass model:
    -- proportional + integral, the integral carries the weight)
    grab_slots = {"Head", "Chest", "Hips", "RightHand", "LeftHand", "LegLeft", "LegRight"},
    point_radius = 0.3,
    point_kp = 0.35, point_ki = 2.0, point_i_max = 6.0,
    point_unit = 5.0,        -- impulse units per 1 m/s at the point (the ~5 kg response of run 6.5)
    point_max_speed = 9.0,   -- m/s the held/pulled point is asked to move at most
    ragdoll_radius = 0.8,
    -- the pull is a toggle (run 6.2: the released event of the right button sometimes came right after the press while
    -- the gun's aiming is blocked, and pulls of people stopped at once): press - pull until grabbed, press again - stop
    pull_timeout = 5.0,
    car_brake = 10.0,        -- s of forced brakes after a car is let go (run 6.2: 'cars drive on' - traffic drivers)
    -- letting go of the button mid-pull: the object keeps this share of its pull velocity (run 6: a ragdoll flew
    -- into V at 12 m/s)
    pull_release_keep = 0.3,
    follow_max = 25.0,       -- m/s: m_shadow.maxSpeed 1000 in/s
    pitch_clamp = 75,        -- deg
    launch_max = 1500 * IN, launch_min = 700 * IN,   -- physcannon_maxforce / minforce (velocities)
    punt_center = 15000, punt_per_kg = 600, punt_mass_cap = {prop = 250, npc = 250, vehicle = 625},
    car_hop = 1.5,           -- m/s up added to a punted car, so its flight starts off the ground
    spin_offset = {prop = 0.25, vehicle = 0.9},
    -- ragdoll impulses act as if the body weighed ~5 kg (run 6.5, Hips readings: 35 units -> +6.4 m/s in a frame);
    -- run 1's '72 per m/s' was read off the feet, which do not follow a ragdoll. Every person impulse (momentum for
    -- 75 kg) is scaled by this - and that is also why people flew far from every push so far
    npc_impulse_scale = 0.07,
    gravity = 9.81,
    gain = 0.5,              -- props (physics): share of the velocity error corrected per frame
    log_frames = 60,
}

local log_lines, holding, pulling, hud, pending = {}, nil, nil, {text = "", t = 0}, {}
local flights = {}   -- thrown cars on their own ballistic path
local checks = {}    -- released cars: did the physics impulse take?
-- the gun is given once the inventory of a (new) player has stopped growing: the same item count for 3 checks
-- a second apart and at least 6 s in (run 6.13 log: a check saw 22 items, gave a gun, 13 s later 821 items with the
-- saved gun - 23 gifts in all, several guns)
local gift = {player = nil, t = 0, done = false, tick = 0, last_n = -1, stable = 0}
local gun_ready, gun_equipped, clock = false, false, 0
local rmb_down = false
local pending_dump = nil
local last_weapon = nil   -- frames until the in-hands weapon is dumped to the log

local function Log(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    line = ok and line or tostring(fmt)
    print("[gravgun] " .. line)
    log_lines[#log_lines + 1] = line
    if #log_lines > 600 then table.remove(log_lines, 1) end
    local f = io.open("log.txt", "w")
    if f then f:write(table.concat(log_lines, "\n"), "\n"); f:close() end
end

local function Hud(text, t) hud.text, hud.t = text, t or 1.5 end

-- Audioware sounds (r6/audioware/gravgun/audios.yml); failures are logged once per sound
local sound_err = {}
local function Sound(name, stop)
    local ok, err = pcall(function()
        if stop then Game.GetAudioSystem():Stop(name) else Game.GetAudioSystem():Play(name) end
    end)
    if not ok and not sound_err[name] then sound_err[name] = true; print("[gravgun] sound " .. name .. ": " .. tostring(err)) end
end

local function V4(x, y, z) return Vector4.new(x, y, z, 1.0) end
local function add(a, b) return V4(a.x + b.x, a.y + b.y, a.z + b.z) end
local function sub(a, b) return V4(a.x - b.x, a.y - b.y, a.z - b.z) end
local function mul(a, s) return V4(a.x * s, a.y * s, a.z * s) end
local function len(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function fmt(v) return v and string.format("(%.2f %.2f %.2f)", v.x, v.y, v.z) or "nil" end

local function ClassName(o)
    local ok, n = pcall(function() return Game.NameToString(o:GetClassName()) end)
    return ok and n or "?"
end

local function Crosshair()
    local player = Game.GetPlayer()
    if not player then return nil end
    local from, fwd = Game.GetTargetingSystem():GetCrosshairData(player)
    return player, from, fwd
end

local function Weapon(player)
    local w = nil
    pcall(function() w = Game.GetTransactionSystem():GetItemInSlot(player, TweakDBID.new("AttachmentSlots.WeaponRight")) end)
    return w
end

local function WeaponKey(w)
    local k = nil
    pcall(function() k = tostring(w:GetEntityID().hash) end)
    return k
end

-- ---------------------------------------------------------------- effects and the view in hands (run 6.10/6.11)
-- Effects (run 6.11; 6.10 drove the Igla's own muzzle lights - entLightComponent, lumens - and nothing showed): one
-- entity of our own (gravgun\fx\empty.ent, spawned by Codeware's StaticEntitySystem like the entSpawner mod does),
-- its components added while it is assembled: point lights "glow" (at the claws), "core" (inside the gun) and
-- "target" (at what is held), and two tubes of gravgun\fx\beam.mesh (an orange hologram: "core" and "halo")
-- stretched by visualScale from the claws to the object. Every frame the entity is put at the claws (the weapon's
-- position + the muzzle offset along its axes), its Z axis to the object; the beam shows while the gun pulls or
-- holds and for a moment on a launch or punt, with a flash of the lights. gameLightComponent SetIntensity, live
-- visualScale with Toggle off/on - as entSpawner does. Units are the engine's (entSpawner's default light is 100).
-- The view in hands: an offset and turn of the gun, applied with SetLocalPosition/SetLocalOrientation to the
-- receiver mesh component (or the Receiver rig it is skinned to); the tuning window (CET overlay) sets both, "Save"
-- writes tune.lua (read at load).
local TUNE = {
    -- owner (run 6.12): 'far too bright; a muted glow of the blocks only; the beam must not light everything up -
    -- just a thin one, like a small lightning bolt': the lights are off by default (only a small flash at the
    -- claws on a launch), the beam is a thin zigzag of BOLTS segments re-drawn every bolt_period seconds
    -- owner (run 6.13): 'the glow wanders by itself - it should just be faintly glowing strips of the textures':
    -- no light at all by default (the flash too); the glow is the model's own (its core rods, mesh emissive)
    fx = {r = 255, g = 150, b = 40, glow_idle = 0, glow_hold = 0, glow_pull = 0, pulse = 0.3, core = 0,
          target = 0, flash = 0, flash_time = 0.12, radius = 2, target_radius = 3, beam_core = 0.006,
          bolt_amp = 0.05, bolt_max = 0.15, bolt_period = 0.05, beam = true, mx = 0, my = 0.50, mz = 0.055,
          muzzle_fire = false, muzzle_lights = false},
    -- the tuning window (owner, run 6.16: 'leave only what is needed - the position and the forces'): the gun's
    -- offset in cm (x right, y forward, z up; applied to the Receiver rig the gun is skinned to, or to the gun
    -- mesh itself - whichever moves it) and the forces in % of CFG.force_scale (punt) / CFG.launch_scale (launch)
    view = {target = 2, x = 0, y = 0, z = 0, pitch = 0, yaw = 0, roll = 0},
    force = {punt_npc = 100, punt_vehicle = 100, launch_npc = 100, launch_vehicle = 100},
}
local SAVED = {view = true, force = true}   -- the sections tune.lua keeps
local VIEW_TARGETS = {"w_shotgun_dual__rostovic_satara__rcv1_01", "Receiver"}
local FX_ENT, BEAM_MESH = "gravgun\\fx\\empty.ent", "gravgun\\fx\\beam.mesh"
local BOLTS = 6
local fx = {flash = 0, flash_to = nil, id = nil, idkey = nil, len = -1, beam_on = nil, cache = {}, warned = {},
            view_key = nil, view_base = {}, view_t = 0, overlay = false, view_log = 0, assembled = false}

local function Serialize(t, ind)
    ind = ind or ""
    local out = {"{"}
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = t[k]
        local s = type(v) == "table" and Serialize(v, ind .. "  ") or (type(v) == "string" and string.format("%q", v) or tostring(v))
        out[#out + 1] = string.format("%s  %s = %s,", ind, k, s)
    end
    out[#out + 1] = ind .. "}"
    return table.concat(out, "\n")
end

local function LoadTune()
    local f = io.open("tune.lua", "r")
    if not f then return end
    local s = f:read("*a"); f:close()
    local ok, t = pcall(function() return (load or loadstring)(s)() end)
    if not ok or type(t) ~= "table" then Log("tune.lua unreadable: %s", tostring(t)); return end
    for sec, vals in pairs(t) do
        if SAVED[sec] and TUNE[sec] and type(vals) == "table" then
            for k, v in pairs(vals) do if TUNE[sec][k] ~= nil then TUNE[sec][k] = v end end
        end
    end
    Log("tune.lua: %s", Serialize({view = TUNE.view, force = TUNE.force}):gsub("%s+", " "))
end

local function SaveTune()
    local f = io.open("tune.lua", "w")
    if not f then Log("tune.lua: cannot write"); return end
    local t = {view = TUNE.view, force = TUNE.force}
    f:write("-- gravgun tuning (written by the in-game window)\nreturn ", Serialize(t), "\n"); f:close()
    Log("tune saved: %s", Serialize(t):gsub("%s+", " "))
end

-- the force of a punt or a launch with the window's percentage (people and cars; props as in CFG)
local function ForceScale(kind, launch)
    local base = launch and CFG.launch_scale[kind] or CFG.force_scale[kind]
    local pct = TUNE.force[(launch and "launch_" or "punt_") .. kind] or 100
    return base * pct / 100
end

local FxReset
local Track   -- the impact watch (defined with the impact damage, used by Primary)
local function Warn(key, msg, ...)
    if fx.warned[key] then return end
    fx.warned[key] = true
    Log(msg, ...)
end

local function FxColor()
    local f = TUNE.fx
    return Color.new({Red = math.floor(f.r), Green = math.floor(f.g), Blue = math.floor(f.b), Alpha = 255})
end

local function FxLight(name, radius, z)
    local c = gameLightComponent.new()
    c.name = name
    c.color = FxColor()
    c.intensity = 0
    c.turnOnByDefault = true
    c.radius = radius
    c.type = ELightType.LT_Point
    c.EV = 0
    c.useInParticles = true
    c.useInTransparents = true
    c:SetLocalPosition(Vector4.new(0, 0, z or 0, 0))
    return c
end

local function FxTube(name, app)
    local c = entMeshComponent.new()
    c.name = name
    c.mesh = ResRef.FromString(BEAM_MESH)
    c.meshAppearance = app
    c.visualScale = Vector3.new(0.01, 0.01, 0.5)
    c:SetLocalPosition(Vector4.new(0, 0, 0.5, 0))
    return c
end

-- called from the EntityBuilder.OnAssemble observer (onInit) for every assembled entity: ours gets its components
local function FxAssemble(entity)
    if not fx.idkey then return end
    local key = nil
    pcall(function() key = tostring(entity:GetEntityID().hash) end)
    if key ~= fx.idkey then return end
    -- (run 6.18 log: the OnAssemble event came twice per entity - every component was added twice, a second set
    -- of beam segments left at their defaults)
    if fx.assembled_key == key then return end
    fx.assembled_key = key
    local f = TUNE.fx
    local ok, err = pcall(function()
        entity:AddComponent(FxLight("glow", f.radius))
        entity:AddComponent(FxLight("core", 0.8, -0.25))
        entity:AddComponent(FxLight("target", f.target_radius, 1))
        for k = 1, BOLTS do entity:AddComponent(FxTube("bolt" .. k, "core")) end
    end)
    fx.assembled = ok
    Log("fx: entity assembled, components %s", ok and "added" or ("failed: " .. tostring(err)))
end

local function FxEntity()
    if not fx.id then return nil end
    local e = nil
    pcall(function() e = Game.GetStaticEntitySystem():GetEntity(fx.id) end)
    return e
end

local function FxSpawn(pos)
    local ok, err = pcall(function()
        local spec = StaticEntitySpec.new()
        spec.templatePath = FX_ENT
        spec.position = pos
        spec.orientation = Quaternion.new(0, 0, 0, 1)
        spec.attached = true
        fx.id = Game.GetStaticEntitySystem():SpawnEntity(spec)
        fx.idkey = tostring(fx.id.hash)
    end)
    fx.len, fx.beam_on, fx.cache, fx.assembled = -1, nil, {}, false
    Log("fx: spawn %s", ok and ("id " .. tostring(fx.idkey)) or ("failed: " .. tostring(err)))
    if not ok then fx.id, fx.idkey = nil, nil; fx.spawn_failed = true end
end

local function FxDespawn()
    if not fx.id then return end
    pcall(function() Game.GetStaticEntitySystem():DespawnEntity(fx.id) end)
    fx.id, fx.idkey = nil, nil
end

-- forget the entity without despawning (it went with the world on a load); the next frame spawns a new one
FxReset = function()
    fx.id, fx.idkey, fx.missing, fx.spawn_failed = nil, nil, 0, false
end

local function Comp(e, name)
    local c = nil
    pcall(function() c = e:FindComponentByName(name) end)
    return c
end

local function FxLightSet(e, name, intensity, radius)
    local c = Comp(e, name)
    if not c then return end
    local f = TUNE.fx
    local col = f.r * 65536 + f.g * 256 + f.b
    local last = fx.cache[name]
    if last and math.abs(last.i - intensity) < 0.02 * math.max(1, last.i) and last.r == radius and last.c == col then return end
    local ok, err = pcall(function()
        if not last or last.c ~= col then c:SetColor(FxColor()) end
        c:SetIntensity(intensity)
        if radius and (not last or last.r ~= radius) then c:SetRadius(radius) end
    end)
    fx.cache[name] = {i = intensity, r = radius, c = col}
    if not ok then Warn("light" .. name, "fx: light %s failed: %s", name, tostring(err)) end
end

-- the rotation that turns +Z onto the unit vector d
local function QFromZ(d)
    local w = 1 + d.z
    if w < 1e-6 then return Quaternion.new(1, 0, 0, 0) end
    local i, j = -d.y, d.x
    local n = math.sqrt(i * i + j * j + w * w)
    return Quaternion.new(i / n, j / n, 0, w / n)
end

local function Rand(a) return (math.random() * 2 - 1) * a end

-- the beam: a zigzag from the claws (the entity's origin) to dist along its Z axis, BOLTS thin segments whose
-- inner points jump sideways (up to bolt_amp of the length, at most bolt_max, none at the ends) every bolt_period
local function FxBeam(e, show, dist, dt)
    local f = TUNE.fx
    fx.bolt_t = (fx.bolt_t or 0) - dt
    if show and (fx.bolt_t <= 0 or math.abs(dist - fx.len) > 0.05) then
        fx.bolt_t, fx.len = f.bolt_period, dist
        local amp = math.min(f.bolt_amp * dist, f.bolt_max)
        local pts = {}
        for k = 0, BOLTS do
            local env = math.sin(math.pi * k / BOLTS)
            pts[k] = {x = Rand(amp * env), y = Rand(amp * env), z = dist * k / BOLTS}
        end
        for k = 1, BOLTS do
            local p0, p1 = pts[k - 1], pts[k]
            local vx, vy, vz = p1.x - p0.x, p1.y - p0.y, p1.z - p0.z
            local L = math.sqrt(vx * vx + vy * vy + vz * vz)
            local c = Comp(e, "bolt" .. k)
            if c and L > 1e-4 then
                local ok, err = pcall(function()
                    c.visualScale = Vector3.new(f.beam_core, f.beam_core, L / 2)
                    c:SetLocalPosition(Vector4.new((p0.x + p1.x) / 2, (p0.y + p1.y) / 2, (p0.z + p1.z) / 2, 0))
                    c:SetLocalOrientation(QFromZ({x = vx / L, y = vy / L, z = vz / L}))
                    if fx.beam_on then c:Toggle(false); c:Toggle(true) end
                end)
                if not ok then Warn("bolt", "fx: bolt failed: %s", tostring(err)) end
            end
        end
        local tl = Comp(e, "target")
        if tl then pcall(function() tl:SetLocalPosition(Vector4.new(0, 0, dist, 0)) end) end
    end
    if show ~= fx.beam_on then
        fx.beam_on = show
        for k = 1, BOLTS do
            local c = Comp(e, "bolt" .. k)
            if c then pcall(function() c:Toggle(show) end) end
        end
    end
end

-- the claws open while the gun pulls or holds (run 6.17): gravgun\gravgun_claws.mesh on the receiver's decal
-- component (the only spare mesh component on the Receiver rig) has chunk 0 closed, chunk 1 open; its chunkMask
-- (1 or 2) picks one, a Toggle off/on shows the change. If the mask cannot be set, the closed claws stay.
local CLAW_COMP = "w_shotgun_dual__rostovic_satara__rcv1_01_decal_n01_default8736"
local claws = {key = nil, open = nil, logged = 0, available = nil}
local function ClawTick(player, open)
    -- only with the claws' mesh in the game (an older archive has the Igla's own decal in that component, which
    -- switching on would show)
    if claws.available == nil then
        claws.available = false
        pcall(function() claws.available = Game.GetResourceDepot():ResourceExists("gravgun\\gravgun_claws.mesh") end)
        Log("claws: %s", claws.available and "gravgun_claws.mesh found" or "no gravgun_claws.mesh in the game - claws stay")
    end
    if not claws.available then return end
    local w = Weapon(player)
    if not w then return end
    local key = WeaponKey(w)
    if key == claws.key and open == claws.open then return end
    local c = Comp(w, CLAW_COMP)
    if not c then Warn("clawcomp", "claws: component %s not found", CLAW_COMP); return end
    local ok, err = pcall(function()
        c.chunkMask = open and 2ULL or 1ULL
        c:Toggle(false)
        c:Toggle(true)
    end)
    claws.key, claws.open = key, open
    if claws.logged < 8 then
        claws.logged = claws.logged + 1
        local m = "?"
        pcall(function() m = tostring(c.chunkMask) end)
        Log("claws %s: %s (mask now %s)", open and "open" or "closed", ok and "ok" or tostring(err), m)
    end
end

-- the claws: the weapon's position + the muzzle offset along its own axes
local function Muzzle(w)
    local f = TUNE.fx
    local v = TUNE.view
    f = {mx = f.mx + v.x / 100, my = f.my + v.y / 100, mz = f.mz + v.z / 100}
    local p, fw, rt, up = w:GetWorldPosition(), w:GetWorldForward(), w:GetWorldRight(), w:GetWorldUp()
    return V4(p.x + fw.x * f.my + rt.x * f.mx + up.x * f.mz, p.y + fw.y * f.my + rt.y * f.mx + up.y * f.mz,
              p.z + fw.z * f.my + rt.z * f.mx + up.z * f.mz), fw
end

-- a launch or punt: the lights flash and the beam reaches to where the object was
local function Flash(to)
    fx.flash, fx.flash_to = TUNE.fx.flash_time, to
    local w = Weapon(Game.GetPlayer())
    if not w then return end
    local effects = {}
    if TUNE.fx.muzzle_lights then effects[#effects + 1] = "muzzle_flash_lights" end
    if TUNE.fx.muzzle_fire then effects[#effects + 1] = "muzzle_flash" end
    for _, e in ipairs(effects) do
        local ok, err = pcall(function() GameObjectEffectHelper.StartEffectEvent(w, CName.new(e), false) end)
        if not ok then Warn(e, "fx: effect %s failed: %s", e, tostring(err)) end
    end
end

-- every frame while the gun is in hands; target: the centre of what is pulled or held (nil: nothing)
local function FxTick(dt, player, target, pull)
    local w = Weapon(player)
    if not w or fx.spawn_failed then return end
    local m, fw = Muzzle(w)
    if not fx.id then FxSpawn(m); return end
    local e = FxEntity()
    if not e then
        -- still spawning, or gone (a load, a teleport far away): after 3 s without it, a new one
        fx.missing = (fx.missing or 0) + dt
        if fx.missing > 3 then Log("fx: the entity is gone, spawning a new one"); FxDespawn(); FxReset() end
        return
    end
    fx.missing = 0
    if not fx.assembled then Warn("notassembled", "fx: the entity is there, but it was not assembled by us (no components)") end
    local f = TUNE.fx
    fx.flash = math.max(0, fx.flash - dt)
    local k = fx.flash > 0 and fx.flash / f.flash_time or 0
    local to = target or (k > 0 and fx.flash_to) or nil
    local dir, dist = fw, 0
    if to then
        local dv = sub(to, m)
        dist = len(dv)
        if dist > 0.05 then dir = mul(dv, 1 / dist) end
    end
    local ok, err = pcall(function()
        local xf = e:GetWorldTransform()
        xf:SetPosition(m)
        xf:SetOrientation(QFromZ(dir))
        e:SetWorldTransform(xf)
    end)
    if not ok then Warn("move", "fx: move failed: %s", tostring(err)) end
    local glow = f.glow_idle
    if target then
        glow = pull and f.glow_pull * (1 + f.pulse * math.sin(clock * 31) * math.sin(clock * 7))
            or f.glow_hold * (1 + f.pulse * math.sin(clock * 6))
    end
    FxLightSet(e, "glow", glow + f.flash * k, f.radius)
    FxLightSet(e, "core", (target and f.core or f.core * 0.3) + 2 * f.core * k, 0.8)
    FxLightSet(e, "target", to and f.target * (1 + 2 * k) or 0, f.target_radius)
    FxBeam(e, f.beam and to ~= nil and dist > 0.3, dist, dt)
end

local function QMul(a, b)
    return Quaternion.new(a.r * b.i + a.i * b.r + a.j * b.k - a.k * b.j,
                          a.r * b.j - a.i * b.k + a.j * b.r + a.k * b.i,
                          a.r * b.k + a.i * b.j - a.j * b.i + a.k * b.r,
                          a.r * b.r - a.i * b.i - a.j * b.j - a.k * b.k)
end

-- the view offset: the base transform is read once per weapon, the offset applied on top every few frames
local function ApplyView(player, dt, force)
    local v0 = TUNE.view
    if not force and not fx.view_used and v0.x == 0 and v0.y == 0 and v0.z == 0 and v0.pitch == 0 and v0.yaw == 0
        and v0.roll == 0 then return end
    fx.view_used = true
    local w = Weapon(player)
    if not w then return end
    local key = WeaponKey(w)
    fx.view_t = fx.view_t - dt
    if key == fx.view_key and fx.view_t > 0 and not force then return end
    fx.view_t = 0.5
    local v = TUNE.view
    for i, n in ipairs(VIEW_TARGETS) do
        local c = nil
        pcall(function() c = w:FindComponentByName(CName.new(n)) end)
        if c then
            local b = fx.view_base[key .. n]
            if not b then
                local ok, p, q = pcall(function() return c:GetLocalPosition(), c:GetLocalOrientation() end)
                b = {p = ok and p or Vector4.new(0, 0, 0, 1), q = ok and q or Quaternion.new(0, 0, 0, 1)}
                fx.view_base[key .. n] = b
                Log("view: %s %s base %s (%s)", n, ClassName(c), fmt(b.p), ok and "read" or tostring(p))
            end
            local on = i == v.target
            local dp = on and Vector4.new(v.x / 100, v.y / 100, v.z / 100, 0) or Vector4.new(0, 0, 0, 0)
            local dq = on and EulerAngles.new(v.roll, v.pitch, v.yaw):ToQuat() or Quaternion.new(0, 0, 0, 1)
            local ok, err = pcall(function()
                c:SetLocalPosition(Vector4.new(b.p.x + dp.x, b.p.y + dp.y, b.p.z + dp.z, 1))
                c:SetLocalOrientation(QMul(b.q, dq))
            end)
            if not ok and not fx.warned["view" .. n] then fx.warned["view" .. n] = true; Log("view: %s failed: %s", n, tostring(err)) end
            if on and (force or key ~= fx.view_key) and fx.view_log < 20 then
                fx.view_log = fx.view_log + 1
                local okr, p = pcall(function() return c:GetLocalPosition() end)
                Log("view: %s offset %.1f %.1f %.1f cm, turn %.1f %.1f %.1f deg -> local %s", n, v.x, v.y, v.z, v.pitch,
                    v.yaw, v.roll, okr and fmt(p) or "?")
            end
        end
    end
    fx.view_key = key
end

-- ---------------------------------------------------------------- the gun item
local function SameId(a, b)
    if not (a and b) then return false end
    local ok, same = pcall(function() return a.hash == b.hash and a.length == b.length end)
    if ok and same then return true end
    return tostring(a) == tostring(b)
end

local function GunId() return TweakDBID.new(GUN) end

local function MakeGun()
    local ok, rec = pcall(function() return TweakDB:GetRecord(GUN) end)
    Log("gun: %s %s", GUN, (ok and rec) and "found (TweakXL)" or "MISSING - is TweakXL installed and r6/tweaks/gravgun.yaml in place?")
    return ok and rec ~= nil
end

local function HasGun(player)
    -- run 4 gave the gun twice: the check is logged now (how many items it saw, whether it found ours)
    local ok, has, n = pcall(function()
        local okl, list = Game.GetTransactionSystem():GetItemList(player)
        local count, sample = 0, {}
        for _, it in ipairs(list or {}) do
            count = count + 1
            local id = it:GetID().id
            if SameId(id, GunId()) then return true, count end
            -- also by the record name (run 6: never found, though given - the id comparison is suspect)
            local okn, nm = pcall(function() return TDBID.ToStringDEBUG(id) end)
            if okn and nm == GUN then return true, count end
            if #sample < 3 then sample[#sample + 1] = tostring(id) .. " / " .. tostring(okn and nm) end
        end
        if count >= 10 then Log("inventory ids e.g. %s; ours %s", table.concat(sample, ", "), tostring(GunId())) end
        return false, count
    end)
    Log("inventory check: %s", ok and string.format("%d items, gun %s", n or -1, has and "found" or "not found") or ("failed: " .. tostring(has)))
    return ok and has
end

-- by record name (the gun's tests too)
local function HasRecord(player, name)
    local ok, has = pcall(function()
        local _, list = Game.GetTransactionSystem():GetItemList(player)
        for _, it in ipairs(list or {}) do
            local okn, nm = pcall(function() return TDBID.ToStringDEBUG(it:GetID().id) end)
            if okn and nm == name then return true end
        end
        return false
    end)
    return ok and has
end

-- the invisible-model A/B tests (r6/tweaks/gravgun.yaml): A - our factory row to the Igla's own .app, B - an
-- untouched copy of it under our path; given once with the gun
local TESTS = {}   -- (run 6.4: the A/B tests answered - no longer given; the records stay in the yaml)

local function GiveGun()
    local player = Game.GetPlayer()
    if not player or not gun_ready then return end
    for _, t in ipairs(TESTS) do
        if not HasRecord(player, t) then
            local okt = pcall(function() Game.AddToInventory(t, 1) end)
            Log("test item %s given: %s", t, tostring(okt))
        end
    end
    if HasGun(player) then Hud("gravity gun: already in the inventory"); return end
    local ok, err = pcall(function() Game.AddToInventory(GUN, 1) end)
    Log("gun given: %s", ok and "yes" or tostring(err))
    Hud(ok and "gravity gun added to the inventory" or "could not add the gun", 3)
end

-- every gravity gun V has (run 6.13: the early gift gave several); keep = the one to leave
local function GunItems(player)
    local items = {}
    pcall(function()
        local _, list = Game.GetTransactionSystem():GetItemList(player)
        for _, it in ipairs(list or {}) do
            local id = it:GetID()
            local okn, nm = pcall(function() return TDBID.ToStringDEBUG(id.id) end)
            if okn and nm == GUN then items[#items + 1] = id end
        end
    end)
    return items
end

local function RemoveExtraGuns()
    local player = Game.GetPlayer()
    if not player then return end
    local ts = Game.GetTransactionSystem()
    local items = GunItems(player)
    local held = nil
    pcall(function() held = ts:GetItemInSlot(player, TweakDBID.new("AttachmentSlots.WeaponRight")):GetItemID() end)
    local function same(a, b)
        local ok, r = pcall(function() return a.id.hash == b.id.hash and a.rngSeed == b.rngSeed end)
        return ok and r
    end
    local keep = items[1]
    for _, id in ipairs(items) do if held and same(id, held) then keep = id end end
    local removed = 0
    for _, id in ipairs(items) do
        if not same(id, keep) then
            local ok = pcall(function() ts:RemoveItem(player, id, 1) end)
            if ok then removed = removed + 1 end
        end
    end
    Log("extra guns: %d found, %d removed", #items, removed)
    Hud(string.format("gravity guns: %d, removed %d", #items, removed), 3)
end

local function GunEquipped(player)
    local ok, yes = pcall(function()
        local it = Game.GetTransactionSystem():GetItemInSlot(player, TweakDBID.new("AttachmentSlots.WeaponRight"))
        return it ~= nil and SameId(it:GetItemID().id, GunId())
    end)
    return ok and yes
end

-- ---------------------------------------------------------------- targets
local function PropBody(ent)
    local ok, comps = pcall(function() return ent:GetComponents() end)
    if not ok or not comps then return nil end
    for _, c in ipairs(comps) do
        local isPhys = false
        pcall(function() isPhys = c:IsA("entPhysicalMeshComponent") end)
        if isPhys then
            local okb, body = pcall(function() return c:CreatePhysicalBodyInterface(0) end)
            if okb and body then return body, c end
        end
    end
    return nil
end

local function Kind(obj)
    local isV, isN = false, false
    pcall(function() isV = obj:IsVehicle() end)
    pcall(function() isN = obj:IsNPC() end)
    if isV then return "vehicle" end
    if isN then return "npc" end
    return "prop"
end

local function FindTarget()
    local player, from, fwd = Crosshair()
    if not player then return nil end
    local obj = nil
    pcall(function() obj = Game.GetTargetingSystem():GetLookAtObject(player, false, false) end)
    if obj then
        local d = len(sub(obj:GetWorldPosition(), from))
        local k = Kind(obj)
        -- a looked-at device or prop without a physical body (terminals, signs): try the physics raycast instead
        if d <= CFG.grab_range + 3 and (k ~= "prop" or PropBody(obj)) then return obj, k, "look-at", d end
    end
    local to = add(from, mul(fwd, CFG.grab_range))
    for _, group in ipairs({"Dynamic", "Vehicle"}) do
        local ok, hit, res = pcall(function()
            return Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(from, to, group, false, false)
        end)
        if ok and hit then
            local ent = nil
            pcall(function() ent = res:GetHitEntity() end)
            if not ent then pcall(function() ent = TraceResult.GetHitEntity(res) end) end
            if ent then return ent, Kind(ent), "raycast " .. group, len(sub(ToVector4(res.position), from)) end
            return nil, nil, "raycast " .. group .. " hit, no entity (world node?)", len(sub(ToVector4(res.position), from))
        end
    end
    -- nothing movable: say what the crosshair is on (run 1: six grabs found nothing within 12 m)
    for _, group in ipairs({"Static", "PlayerBlocker", "Terrain", "Water"}) do
        local ok, hit, res = pcall(function()
            return Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(from, to, group, false, false)
        end)
        if ok and hit then
            local mat = "?"
            pcall(function() mat = Game.NameToString(res.material) end)
            return nil, nil, "only " .. group .. " (" .. mat .. ")", len(sub(ToVector4(res.position), from))
        end
    end
    return nil, nil, "nothing within " .. CFG.grab_range .. " m", nil
end

local function Mass(h)
    if h.kind == "vehicle" then
        local ok, m = pcall(function() return h.obj:GetTotalMass() end)
        return (ok and m and m > 0) and m or 1500
    elseif h.kind == "prop" and h.body then
        local ok, m = pcall(function() return h.body:GetMass() end)
        return (ok and m and m > 0) and m or 20
    end
    return 75   -- NPC
end

local function Slot(npc, name)
    local p = nil
    pcall(function()
        local ok, wt = npc:GetSlotComponent():GetSlotTransform(CName.new(name))
        if ok and wt then p = WorldPosition.ToVector4(wt.Position) end
    end)
    return p
end

-- an NPC's body: the Hips slot follows the ragdoll (the entity position stays at the feet on the ground - run 4);
-- SlotComponent.GetSlotTransform (the game reads Hips/Chest of ragdolled NPCs in aiStatusEffectTask.script)
local function Hips(npc)
    local p = nil
    pcall(function()
        local ok, wt = npc:GetSlotComponent():GetSlotTransform(CName.new("Hips"))
        if ok and wt then p = WorldPosition.ToVector4(wt.Position) end
    end)
    return p
end

local function Position(h)
    if h.kind == "npc" then
        local p = (h.slot and Slot(h.obj, h.slot)) or Hips(h.obj)
        if p then return p end
        if not h.no_hips then h.no_hips = true; Log("no Hips slot on %s - using feet + 1 m", ClassName(h.obj)) end
        return add(h.obj:GetWorldPosition(), V4(0, 0, 1))
    end
    if h.kind == "prop" and h.body then
        local ok, t = pcall(function() return h.body:GetTransform() end)
        if ok and t and t.position then return ToVector4(t.position) end
    end
    return h.obj:GetWorldPosition()
end

local function Velocity(h, pos, dt)
    local diff = (h.last_pos and dt > 0) and mul(sub(pos, h.last_pos), 1 / dt) or nil
    local v = nil
    if h.kind == "vehicle" then
        pcall(function() v = h.obj:GetLinearVelocity() end)
    elseif h.kind == "prop" and h.body then
        pcall(function() v = h.body:GetLinearVelocity() end)
    end
    if v then
        v = V4(v.x, v.y, v.z)
        -- a reported zero while the object visibly moves: the getter does not work, use the position difference
        if diff and len(v) < 0.01 and len(diff) > 0.3 then h.bad_vel = true end
        if not h.bad_vel then return v, "reported" end
    end
    if diff then
        if h.kind == "npc" then   -- a ragdoll's hips jitter: smoothed
            h.vs = h.vs and add(mul(h.vs, 0.5), mul(diff, 0.5)) or diff
            return h.vs, "hips"
        end
        return diff, "diff"
    end
    return V4(0, 0, 0), "none"
end

-- one impulse (kg m/s) on the object, at its position (+ offset: spin)
local function Impulse(h, imp, pos, offset)
    if h.kind == "prop" and h.body then
        local ok = pcall(function() h.body:AddLinearImpulse(imp, offset == nil, offset or V4(0, 0, 0)) end)
        if ok then return "body" end
    end
    if h.kind == "npc" then
        local ok = pcall(function()
            -- launches, punts and releases push the whole body from the hips - the calibration's point - not the held
            -- point (run 6.7: launched by a hand, people barely moved)
            local at = Hips(h.obj) or pos
            h.obj:QueueEvent(CreateRagdollApplyImpulseEvent(at, mul(imp, CFG.npc_impulse_scale), CFG.ragdoll_radius))
        end)
        return ok and "ragdoll" or "ragdoll failed"
    end
    local at = offset and add(pos, offset) or pos
    local ok = pcall(function()
        local e = PhysicalImpulseEvent.new()
        e.worldPosition = Vector3.new(at.x, at.y, at.z)
        e.worldImpulse = Vector3.new(imp.x, imp.y, imp.z)
        e.radius = 1.0
        h.obj:QueueEvent(e)
    end)
    return ok and "event" or "event failed"
end

-- a lifeless ragdoll: no power pose (the 'living' one tries to keep a stance and fought the gun)
local function Ragdoll(npc)
    return pcall(function()
        if not ScriptedPuppet.CanRagdoll(npc) then return end
        local ok = pcall(function() npc:QueueEvent(CreateForceRagdollNoPowerPoseEvent("gravgun")) end)
        if not ok then npc:QueueEvent(CreateForceRagdollEvent("gravgun")) end
    end)
end

-- an object's current facing as EulerAngles (kept while it is carried)
local function Facing(obj)
    local e = nil
    pcall(function() e = Vector4.ToRotation(obj:GetWorldForward()) end)
    if not e then pcall(function() e = GetSingleton("Quaternion"):ToEulerAngles(obj:GetWorldOrientation()) end) end
    return e or EulerAngles.new(0, 0, 0)
end

local function Teleport(obj, pos, angles)
    return pcall(function() Game.GetTeleportationFacility():Teleport(obj, pos, angles) end)
end

-- ---------------------------------------------------------------- HL2 rules
local function SimpleSpline(x) local x2 = x * x; return 3 * x2 - 2 * x2 * x end

-- Pickup_DefaultPhysGunLaunchVelocity: full speed up to 100 kg, spline down to the minimum at 600 kg
local function LaunchSpeed(m)
    if m <= 100 then return CFG.launch_max end
    local t = math.min(1, (math.min(m, 1000) - 100) / 500)
    return CFG.launch_max + (CFG.launch_min - CFG.launch_max) * SimpleSpline(t)
end

-- PuntVPhysics: ApplyForceCenter(15000) + ApplyForceOffset(min(m, cap) * 600), kg in/s -> velocity change m/s
local function PuntSpeed(kind, m)
    return (CFG.punt_center + math.min(m, CFG.punt_mass_cap[kind]) * CFG.punt_per_kg) / m * IN
end

-- the pull acceleration (m/s^2): pull impulse every 0.1 s, under 50 kg scaled by (m + 0.5) / 50
local function PullAccel(kind, m)
    local f = CFG.pull_force[kind]
    if m < 50 then f = f * (m + 0.5) / 50 end
    return f * IN / CFG.pull_period / m
end

local function HoldDist(kind) return 24 * IN + CFG.player_radius + CFG.half_size[kind] end
local function AttachDist(kind) return CFG.attach[kind] or (HoldDist(kind) + CFG.attach_extra) end

local function Yaw(v) local e = nil; pcall(function() e = Vector4.ToRotation(v) end); return e and e.yaw or 0 end

-- aim with HL2's pitch clamp
local function AimForward(fwd)
    local h = math.sqrt(fwd.x * fwd.x + fwd.y * fwd.y)
    local pitch = math.deg((math.atan2 or math.atan)(fwd.z, h))
    local c = math.max(-CFG.pitch_clamp, math.min(CFG.pitch_clamp, pitch))
    if c == pitch or h < 1e-6 then return fwd end
    local r = math.cos(math.rad(c)) / h
    return V4(fwd.x * r, fwd.y * r, math.sin(math.rad(c)))
end

local function Centre(o)
    if o.kind == "npc" then return Position(o) end
    return add(o.carry and o.p or Position(o), V4(0, 0, CFG.centre_up[o.kind]))
end

-- ---------------------------------------------------------------- objects: start, pull, attach, release
local function NewObject(obj, kind)
    local o = {obj = obj, kind = kind, frames = 0}
    if kind == "prop" then
        o.body = PropBody(obj)
        if not o.body then return nil end
        pcall(function() o.body:SetIsKinematic(false) end)
    elseif kind == "npc" then
        -- people: a ragdoll from the start, moved by ragdoll impulses (run 6.3: a per-frame Teleport does not move a
        -- living NPC - its movement controller owns the root; mods that throw NPCs use ragdoll + impulse)
        o.rag = true
        Ragdoll(obj)
        o.wait = 2   -- the ragdoll needs a frame before impulses act
        -- the point to hold it by: the body part nearest the crosshair ray
        local _, from, fwd = Crosshair()
        local best, bd = nil, 1e9
        for _, name in ipairs(CFG.grab_slots) do
            local sp = Slot(obj, name)
            if sp then
                local r = sub(sp, from)
                local t = math.max(0, r.x * fwd.x + r.y * fwd.y + r.z * fwd.z)
                local dd = len(sub(r, mul(fwd, t)))
                if dd < bd then best, bd = name, dd end
            end
        end
        o.slot = best or "Chest"
        o.I = V4(0, 0, 0)
        Log("person held by %s (%.2f m off the crosshair)", o.slot, bd)
    else
        -- cars: out of the traffic lane system (run 6.3: a carried car snapped back to its place - a traffic car is
        -- placed by its lane until its physics is enabled, natively, as on a crash: VehicleObject.ForceEnablePhysics
        -- from Let There Be Flight), the driver's actions ended, gravity off while carried, brakes on
        o.carry = true
        o.angles = Facing(obj)
        o.p = obj:GetWorldPosition()
        local res = {}
        for _, f in ipairs({"ForceEnablePhysics", "EndActions"}) do
            res[#res + 1] = f .. " " .. tostring(pcall(function() obj[f](obj) end))
        end
        res[#res + 1] = "gravity off " .. tostring(pcall(function() obj:EnableGravity(false) end))
        pcall(function() obj:ForceBrakesFor(600.0) end)
        Log("car freed: %s", table.concat(res, ", "))
    end
    o.v = V4(0, 0, 0)
    o.m = Mass(o)
    return o
end

-- hand a carried object back to physics with velocity v (people: ragdoll + impulse; cars: their own flight)
local function ToPhysics(o, v, spin)
    if o.rag then   -- a ragdoll: the velocity change it still needs (it already moves with its own)
        local cur = o.v or V4(0, 0, 0)
        pending[#pending + 1] = {h = o, imp = mul(sub(v, cur), o.m), frames = o.wait and o.wait > 0 and 2 or 0}
        return
    end
    if not o.carry then return end
    -- a car: physics back with gravity and the velocity as an impulse; checked a few frames later - if it did not take
    -- (impulses on a car were ignored in runs 1-4), the gun flies it on its own path instead
    -- (run 6.5: a car's physics never took the impulse, and a dropped car hung in the air): every released car falls
    -- on the gun's own path until it is on the ground
    pcall(function() o.obj:EnableGravity(true) end)
    flights[#flights + 1] = {h = o, p = o.p, v = v, t = 0, yaw = 0, spin = spin or 0, brake = true}
end

local function Attach(o)
    pulling = nil
    local _, _, fwd = Crosshair()
    o.yaw0 = Yaw(fwd)                     -- V's yaw at the grab: the object turns with V from here
    o.frames = 0
    holding = o
    Sound("gravgun_pickup"); Sound("gravgun_hold")
    Log("grab %s %s, mass %.0f, hold at %.2f m", o.kind, ClassName(o.obj), o.m, HoldDist(o.kind))
    Hud("holding " .. o.kind, 1.2)
end

local function Drop()
    local o = holding
    holding = nil
    if not o then return end
    Sound("gravgun_hold", true); Sound("gravgun_drop")
    ToPhysics(o, o.v, 0)
    Log("drop %s, velocity %s", o.kind, fmt(o.v))
end

local function StopPull()
    local o = pulling
    pulling = nil
    if not o then return end
    o.v = mul(o.v, CFG.pull_release_keep)
    ToPhysics(o, o.v, 0)
    Log("pull stopped: %s at %s m/s", o.kind, fmt(o.v))
end

-- right mouse pressed: drop what is held, else start pulling (or grab at once if it is already close)
local function SecondaryDown()
    rmb_down = true
    if holding then Drop(); return end
    if pulling then StopPull(); return end
    local obj, kind, how, d = FindTarget()
    if not obj then
        Log("pull: nothing (%s, %.1f m)", tostring(how), d or -1)
        Hud("nothing to grab" .. (how and (" - " .. how) or ""), 1.5)
        Sound("gravgun_dryfire")
        return
    end
    if d and d > CFG.range[kind] then
        Hud(string.format("too far (%.0f m)", d), 1.2); Sound("gravgun_dryfire"); return
    end
    local o = NewObject(obj, kind)
    if not o then
        Log("pull: %s (%s) has no physical body", ClassName(obj), how)
        Hud("can't grab " .. ClassName(obj), 1.5); Sound("gravgun_tooheavy")
        return
    end
    local _, from = Crosshair()
    local dist = len(sub(Centre(o), from))
    Log("pull %s %s via %s at %.1f m, mass %.0f, accel %.1f m/s2, attach at %.2f m", kind, ClassName(obj), how, dist,
        o.m, PullAccel(kind, o.m), AttachDist(kind))
    if dist <= AttachDist(kind) then Attach(o) else pulling = o; Sound("gravgun_claws_open") end
end

local function SecondaryUp()
    rmb_down = false   -- the pull is a toggle now: letting go of the button does not stop it
end

-- left mouse: launch the held object, else punt what is under the crosshair
local function Primary()
    local _, from, fwd = Crosshair()
    if holding then
        local o = holding
        holding = nil
        Sound("gravgun_hold", true); Sound("gravgun_launch" .. math.random(1, 4))
        local s = LaunchSpeed(o.m) * ForceScale(o.kind, true)
        local v = add(o.v, mul(fwd, s))
        if o.carry then
            ToPhysics(o, v, (math.random() < 0.5 and -1 or 1) * 120)
        else
            Impulse(o, mul(fwd, s * o.m), Position(o), V4(0, 0, CFG.spin_offset.prop))
        end
        Log("launch %s (%.0f kg) at +%.1f m/s: velocity %s", o.kind, o.m, s, fmt(v))
        local okc, c = pcall(Centre, o)
        Flash(okc and c or nil)
        Track(o)
        Hud("launched " .. o.kind, 1)
        return
    end
    if pulling then StopPull() end
    local obj, kind, how, d = FindTarget()
    if not obj or (d and d > CFG.range[kind]) then Hud("nothing to punt", 1.2); Sound("gravgun_dryfire"); return end
    local o = NewObject(obj, kind)
    if not o then Sound("gravgun_dryfire"); return end
    Sound("gravgun_launch" .. math.random(1, 4))
    local dir = V4(fwd.x, fwd.y, fwd.z < 0 and fwd.z * -0.65 or fwd.z)
    dir = mul(dir, 1 / len(dir))
    local s = PuntSpeed(kind, o.m) * ForceScale(kind, false)
    local v = mul(dir, s)
    if kind == "vehicle" then v = add(v, V4(0, 0, CFG.car_hop)) end
    if o.carry or o.rag then ToPhysics(o, v, kind == "vehicle" and (math.random() < 0.5 and -1 or 1) * 60 or 0)
    else Impulse(o, mul(v, o.m), Position(o), V4(0, 0, CFG.spin_offset.prop)) end
    Log("punt %s %s via %s at %.1f m (%.0f kg): %.1f m/s", kind, ClassName(obj), how, d or -1, o.m, s)
    local okc, c = pcall(Centre, o)
    Flash(okc and c or nil)
    Track(o)
end

-- ---------------------------------------------------------------- per frame
local function Alive(o)
    local attached = true
    pcall(function() attached = o.obj:IsAttached() end)
    return o.obj ~= nil and attached
end

-- a ragdoll: skip the frames it needs to start; re-ragdoll every second so it does not get up while held
local function RagdollTick(o, dt)
    if not o.rag then return false end
    o.rt = (o.rt or 0) + dt
    if o.rt > 4.0 then o.rt = 0; Ragdoll(o.obj) end   -- only now and then, in case it started to get up
    if o.wait and o.wait > 0 then
        o.wait = o.wait - 1
        o.last_pos = Position(o)
        return true
    end
    return false
end

-- a person's point towards a wanted velocity: proportional + integral (the integral ends up carrying the weight)
local function PointControl(o, want, dt)
    local pos = Position(o)
    local v = Velocity(o, pos, dt)
    o.v, o.last_pos = v, pos
    local ws = len(want)
    if ws > CFG.point_max_speed then want = mul(want, CFG.point_max_speed / ws) end
    local err = sub(want, v)
    o.I = add(o.I or V4(0, 0, 0), mul(err, dt))
    local il = len(o.I)
    if il > CFG.point_i_max then o.I = mul(o.I, CFG.point_i_max / il) end
    local dv = add(mul(err, CFG.point_kp), mul(o.I, CFG.point_ki * dt * 10))
    local dl = len(dv)
    if dl > 2.0 then dv = mul(dv, 2.0 / dl) end   -- at most 2 m/s change a frame
    pcall(function()
        o.obj:QueueEvent(CreateRagdollApplyImpulseEvent(pos, mul(dv, CFG.point_unit), CFG.point_radius))
    end)
    return pos, v
end

-- pulled: the pull acceleration towards the gun; carried objects move by it, props and ragdolls get it as an impulse
local function Pull(o, dt)
    if RagdollTick(o, dt) then return end
    o.t = (o.t or 0) + dt
    if o.t > CFG.pull_timeout then Log("pull timed out after %.1f s", o.t); StopPull(); return end
    local player, from, fwd = Crosshair()
    local c = Centre(o)
    local to = sub(from, c)
    local dist = len(to)
    if dist <= AttachDist(o.kind) then Attach(o); return end
    local dir = mul(to, 1 / dist)
    -- coming in fast and nearly there: grab now rather than fly past V (run 6.5: a body passed at ~2.6 m and flew on)
    local closing = o.v.x * dir.x + o.v.y * dir.y + o.v.z * dir.z
    if dist <= AttachDist(o.kind) + 1.5 and closing > 4 then Attach(o); return end
    local a = PullAccel(o.kind, o.m)
    if o.carry then
        -- sideways drift is damped, so it comes along the line to the gun
        local along = o.v.x * dir.x + o.v.y * dir.y + o.v.z * dir.z
        local side = sub(o.v, mul(dir, along))
        o.v = add(mul(dir, along + a * dt), mul(side, math.max(0, 1 - 4 * dt)))
        local sp = len(o.v)
        if sp > CFG.pull_max_speed then o.v = mul(o.v, CFG.pull_max_speed / sp) end
        o.p = add(o.p, mul(o.v, dt))
        Teleport(o.obj, o.p, o.angles)
    else
        if o.rag then
            -- the point is asked to come to the gun at a speed rising with HL2's pull acceleration
            o.ps = math.min(CFG.point_max_speed, (o.ps or 0) + a * dt)
            PointControl(o, mul(dir, o.ps), dt)
            o.frames = o.frames + 1
            if o.frames <= CFG.log_frames and (o.frames <= 5 or o.frames % 10 == 0) then
                Log("pull npc f%d dist %.2f speed %.2f wanted %.1f at %s (%s)", o.frames, dist, len(o.v), o.ps, fmt(c), o.slot)
            end
            return
        end
        local pos = Position(o)
        o.v = Velocity(o, pos, dt)
        local imp = mul(dir, a * dt * o.m)
        if o.rag then
            -- a body floats to the gun (weight carried, sideways drift damped) instead of being dragged on the ground;
            -- its speed is capped like a carried object's
            local along = o.v.x * dir.x + o.v.y * dir.y + o.v.z * dir.z
            local side = sub(o.v, mul(dir, along))
            imp = add(imp, add(V4(0, 0, CFG.gravity * dt * o.m), mul(side, -o.m * math.min(1, 4 * dt))))
            if along > CFG.pull_max_speed then imp = add(imp, mul(dir, -(along - CFG.pull_max_speed) * o.m)) end
        end
        Impulse(o, imp, pos)
        o.last_pos = pos
    end
    o.frames = o.frames + 1
    if o.frames <= CFG.log_frames and (o.frames <= 5 or o.frames % 10 == 0) then
        Log("pull %s f%d dist %.2f speed %.2f accel %.1f at %s", o.kind, o.frames, dist, len(o.v), a, fmt(c))
    end
end

-- held: a damped follow of the point in front of the eyes; the object turns with V
local function Hold(o, dt)
    if RagdollTick(o, dt) then return end
    local player, from, fwd = Crosshair()
    local aim = AimForward(fwd)
    local point = add(from, mul(aim, HoldDist(o.kind)))
    local c = Centre(o)
    local want = mul(sub(point, c), 1 / CFG.follow_time[o.kind])
    local ws = len(want)
    if ws > CFG.follow_max then want = mul(want, CFG.follow_max / ws) end
    if o.carry then
        o.v = add(o.v, mul(sub(want, o.v), math.min(1, dt / 0.05)))
        o.p = add(o.p, mul(o.v, dt))
        local a = o.angles
        Teleport(o.obj, o.p, EulerAngles.new(a.roll, a.pitch, a.yaw + (Yaw(fwd) - o.yaw0)))
    elseif o.rag then
        PointControl(o, want, dt)
    else
        local pos = Position(o)
        local vel = Velocity(o, pos, dt)
        local imp = add(mul(sub(want, vel), o.m * CFG.gain), V4(0, 0, CFG.gravity * dt * o.m))
        local cap = o.m * 3.0   -- at most 3 m/s change a frame, whatever the readings
        if len(imp) > cap then imp = mul(imp, cap / len(imp)) end
        Impulse(o, imp, pos)
        o.v, o.last_pos = vel, pos
    end
    o.frames = o.frames + 1
    if o.frames <= CFG.log_frames and (o.frames <= 5 or o.frames % 10 == 0) then
        Log("hold %s f%d off %.2f speed %.2f at %s", o.kind, o.frames, len(sub(point, c)), len(o.v), fmt(c))
    end
end

-- a thrown/punted/dropped car: ballistic, teleported, spinning; ends on a hit ahead, on landing or after 3 s
-- the ground (or a roof) under a point: z of the first Static/Terrain/Water hit straight down, or nil
local function GroundZ(p, above, below)
    local best = nil
    for _, group in ipairs({"Static", "Terrain", "Water"}) do
        pcall(function()
            local ok, res = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(
                add(p, V4(0, 0, above)), add(p, V4(0, 0, -below)), group, false, false)
            if ok then
                local z = ToVector4(res.position).z
                if not best or z > best then best = z end
            end
        end)
    end
    return best
end

-- a thrown/punted/dropped car: ballistic, teleported, spinning, until its floor touches the ground; it bounces off
-- walls (horizontal velocity x -0.25) and keeps falling; at the end it is put on the ground (run 6.6: it ended on a
-- 'landing' seen 1.6 m above the floor, on a wall hit or after 3 s - and hung in the air, physics never took it)
local function Fly(f, dt)
    f.t = f.t + dt
    f.v = add(f.v, V4(0, 0, -CFG.gravity * dt))
    local nextp = add(f.p, mul(f.v, dt))
    local function Hit(a, b)
        for _, group in ipairs({"Static", "Terrain", "Water"}) do
            local ok, h = pcall(function()
                local r = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(a, b, group, false, false)
                return r
            end)
            if ok and h then return group end
        end
        return nil
    end
    -- a wall ahead (a ray at mid-body height): bounce back a little, keep falling
    local mid = V4(0, 0, 0.8)
    if f.t > 0.15 and (f.cool or 0) <= 0 then
        local horiz = V4(f.v.x, f.v.y, 0)
        if len(horiz) > 0.5 then
            local ahead = add(nextp, mul(horiz, 0.12))
            local hit = Hit(add(f.p, mid), add(ahead, mid))
            if hit then
                f.v = V4(-f.v.x * 0.25, -f.v.y * 0.25, f.v.z)
                f.cool = 0.3
                Log("car bounced off %s", hit)
                nextp = add(f.p, mul(f.v, dt))
            end
        end
    end
    f.cool = (f.cool or 0) - dt
    -- the floor reaching the ground: from 0.4 m above the floor down to the next position
    local g = (f.v.z < 0) and GroundZ(nextp, 0.4, 0.05) or nil
    if g or f.t > 8.0 then
        local z = g or GroundZ(f.p, 2.0, 200.0)
        if z then f.p = V4(nextp.x, nextp.y, z + 0.05) end
        local a = f.h.angles
        Teleport(f.h.obj, f.p, EulerAngles.new(a.roll, a.pitch, a.yaw + f.yaw))
        pcall(function() f.h.obj:PhysicsWakeUp() end)
        -- the traffic driver would just drive on (run 6.2): brakes for a while (replaces the grab's long brake)
        if f.brake then pcall(function() f.h.obj:ForceBrakesFor(CFG.car_brake) end) end
        local hv = V4(f.v.x, f.v.y, 0)
        pending[#pending + 1] = {h = f.h, imp = mul(hv, Mass(f.h)), frames = 2}
        Log("car flight ended after %.2f s (%s), put on the ground at z %s", f.t, g and "landed" or "time",
            z and string.format("%.2f", z) or "?")
        return true
    end
    f.p = nextp
    f.yaw = f.yaw + f.spin * dt
    local a = f.h.angles
    Teleport(f.h.obj, f.p, EulerAngles.new(a.roll, a.pitch, a.yaw + f.yaw))
    return false
end

-- what the gun in hands is made of (owner: 'the weapon's model is not shown'): the weapon entity and the items in
-- its part slots, every component with a mesh - class, name, enabled, chunk mask, mesh path
local function DumpWeapon(player)
    local ts = Game.GetTransactionSystem()
    local w = ts:GetItemInSlot(player, TweakDBID.new("AttachmentSlots.WeaponRight"))
    if not w then Log("dump: nothing in the right hand"); return end
    local function Comps(ent, tag)
        local okA, app = pcall(function() return Game.NameToString(ent:GetCurrentAppearanceName()) end)
        local okR, rec = pcall(function() return TDBID.ToStringDEBUG(ent:GetItemID().id) end)
        Log("dump %s: %s, record %s, appearance %s", tag, ClassName(ent), okR and rec or "?", okA and app or "?")
        local ok, comps = pcall(function() return ent:GetComponents() end)
        if not ok or not comps then Log("  components: %s", ok and "none" or tostring(comps)); return end
        local n, others = 0, {}
        for _, c in ipairs(comps) do
            n = n + 1
            local hasMesh = false
            pcall(function() hasMesh = c:IsA("entMeshComponent") or c:IsA("entSkinnedMeshComponent") end)
            if hasMesh then
                local path, en, mask, mapp = "?", "?", "?", "?"
                pcall(function() path = tostring(c.mesh.hash) end)
                pcall(function() path = ResRef.ToString and ResRef.ToString(c.mesh) or path end)
                pcall(function() en = tostring(c:IsEnabled()) end)
                pcall(function() mask = tostring(c.chunkMask) end)
                pcall(function() mapp = Game.NameToString(c.meshAppearance) end)
                Log("  %s %s enabled %s mask %s app %s mesh %s", ClassName(c), Game.NameToString(c:GetName()), en, mask, mapp, path)
            else
                local nm = "?"
                pcall(function() nm = Game.NameToString(c:GetName()) end)
                others[#others + 1] = ClassName(c) .. ":" .. nm
            end
        end
        Log("  %d components; without a mesh: %s", n, table.concat(others, ", "))
    end
    Comps(w, "weapon")
    for _, slot in ipairs({"Receiver", "Barrel", "Magazine", "MagazineEmpty"}) do
        local okp, part = pcall(function() return ts:GetItemInSlot(w, TweakDBID.new("AttachmentSlots." .. slot)) end)
        if okp and part then Comps(part, "part " .. slot) else Log("dump part %s: none", slot) end
    end
    -- does the game see our files at all (Codeware ResourceDepot)?
    pcall(function()
        local depot = Game.GetResourceDepot()
        local res = {}
        for _, f in ipairs({"gravgun\\gravgun.app", "gravgun\\test_copy.app", "gravgun\\gravgun.mesh",
                            "gravgun\\gravgun_factory.csv",
                            "base\\weapons\\firearms\\shotgun_dual\\rostovic_igla\\w_shotgun_dual__rostovic_igla.app"}) do
            local ok, e = pcall(function() return depot:ResourceExists(f) end)
            res[#res + 1] = f .. "=" .. tostring(ok and e or ("err " .. tostring(e)))
        end
        local oka, ea = pcall(function() return depot:ArchiveExists("gravgun.archive") end)
        Log("  depot: %s; archive gravgun.archive=%s", table.concat(res, ", "), tostring(oka and ea))
    end)
end

-- ---------------------------------------------------------------- impact damage (run 6.17)
-- owner: 'damage from what is thrown' (HL2's physics damage). For CFG.impact.time after a launch or punt the thrown
-- person or car is watched every CFG.impact.period: NPCs within the radius of the stretch it flew since the last
-- check (a segment - at 30 m/s it moves 3 m per check), while it is faster than min_speed, take damage (% of their
-- health per m/s over min_speed) and are knocked down (ragdoll + a push along the flight); a thrown person whose
-- speed drops sharply (a wall, the ground) takes damage itself. Damage: StatPoolsSystem Health in %, V the
-- instigator (the game's own consequences follow). Victims: TargetingSystem parts around V.
CFG.impact = {time = 2.5, period = 0.1, min_speed = 6, radius = {npc = 1.0, vehicle = 2.4},
              dmg = {npc = 4, vehicle = 6}, self_drop = 8, self_dmg = 3, push = 0.5, search = 60, max_speed = 70}
local thrown = {}

local function KeyOf(obj)
    local k = nil
    pcall(function() k = tostring(obj:GetEntityID().hash) end)
    return k
end

-- run 6.17: the damage was logged but did nothing visible (owner: 'does not work'). Now: the health is read before
-- and 0.3 s after (logged, so a run shows whether it changed); a lethal hit sets Health to 0 the way the game's own
-- scripts kill (RequestSettingStatPoolValue ..., 0) and also calls Kill; a partial one subtracts the percentage.
local health_checks = {}

local function HealthPct(npc)
    local v = nil
    pcall(function() v = Game.GetStatPoolsSystem():GetStatPoolValue(npc:GetEntityID(), gamedataStatPoolType.Health, true) end)
    return v
end

local function Damage(npc, pct, why)
    if pct <= 0 then return end
    pct = math.min(pct, 100)
    local before = HealthPct(npc)
    if before and before <= 0 then return end   -- already dead
    local lethal = pct >= 100 or (before and before - pct <= 0)
    local sps = Game.GetStatPoolsSystem()
    local ok, err = pcall(function()
        if lethal then
            sps:RequestSettingStatPoolValue(npc:GetEntityID(), gamedataStatPoolType.Health, 0, Game.GetPlayer())
        else
            sps:RequestChangingStatPoolValue(npc:GetEntityID(), gamedataStatPoolType.Health, -pct, Game.GetPlayer(), false, true)
        end
    end)
    local killed = nil
    if lethal then
        killed = pcall(function() npc:Kill(Game.GetPlayer(), false, false) end)
    end
    Log("impact: %s %s -%.0f%% health (was %s)%s%s", why, ClassName(npc), pct, before and string.format("%.0f%%", before) or "?",
        ok and "" or (" request failed: " .. tostring(err)), lethal and (" kill " .. (killed and "called" or "failed")) or "")
    health_checks[#health_checks + 1] = {npc = npc, before = before, t = 0.3}
end

local function HealthChecks(dt)
    for i = #health_checks, 1, -1 do
        local h = health_checks[i]
        h.t = h.t - dt
        if h.t <= 0 then
            table.remove(health_checks, i)
            local dead = nil
            pcall(function() dead = h.npc:IsDead() end)
            local now = HealthPct(h.npc)
            Log("impact check: health %s -> %s, dead %s", h.before and string.format("%.0f%%", h.before) or "?",
                now and string.format("%.0f%%", now) or "?", tostring(dead))
        end
    end
end

local function NPCsAround(radius)
    local out = {}
    local ok, err = pcall(function()
        local q = Game["TSQ_NPC;"]()
        q.maxDistance = radius
        q.testedSet = TargetingSet.Complete
        local _, parts = Game.GetTargetingSystem():GetTargetParts(Game.GetPlayer(), q)
        for _, part in ipairs(parts or {}) do
            local e = nil
            pcall(function() e = TS_TargetPartInfo.GetComponent(part):GetEntity() end)
            local k = e and KeyOf(e)
            if k then out[k] = e end
        end
    end)
    if not ok then Warn("npcsaround", "impact: the NPC search failed: %s", tostring(err)) end
    return out
end

-- the distance from point c to the segment a-b
local function SegDist(a, b, c)
    local ab, ac = sub(b, a), sub(c, a)
    local l2 = ab.x * ab.x + ab.y * ab.y + ab.z * ab.z
    local t = l2 > 1e-9 and math.max(0, math.min(1, (ac.x * ab.x + ac.y * ab.y + ac.z * ab.z) / l2)) or 0
    return len(sub(c, add(a, mul(ab, t))))
end

Track = function(o)
    if o.kind ~= "npc" and o.kind ~= "vehicle" then return end
    local k = KeyOf(o.obj)
    thrown[#thrown + 1] = {o = o, t = 0, tick = 0, hit = {[k or "?"] = true}}
end

local function ThrownPos(o)
    if o.kind == "npc" then return Position(o) end   -- the hips
    local p = nil
    pcall(function() local q = o.obj:GetWorldPosition(); p = V4(q.x, q.y, q.z + CFG.centre_up.vehicle) end)
    return p
end

local function ImpactTick(dt)
    local I = CFG.impact
    for i = #thrown, 1, -1 do
        local w = thrown[i]
        w.t, w.tick = w.t + dt, w.tick + dt
        if w.t > I.time then
            table.remove(thrown, i)
        elseif w.tick >= I.period then
            local step = w.tick
            w.tick = 0
            local p = ThrownPos(w.o)
            local v, sp = nil, nil
            if p and w.last then
                v = mul(sub(p, w.last), 1 / step)
                sp = len(v)
                -- a jump of the tracked point (the hips of a ragdoll being re-laid, run 6.17: '246 m/s'): not a speed
                if sp > I.max_speed then sp, p = nil, nil; w.sp = nil end
            end
            if sp then
                if w.o.kind == "npc" and w.sp and w.t > 0.15 and w.sp - sp > I.self_drop and not w.selfhit then
                    w.selfhit = true
                    Damage(w.o.obj, (w.sp - sp - I.self_drop) * I.self_dmg + 10, string.format("hit something at %.0f m/s:", w.sp))
                end
                if sp > I.min_speed then
                    for key, npc in pairs(NPCsAround(I.search)) do
                        if not w.hit[key] then
                            local np, dead = nil, false
                            pcall(function() local q = npc:GetWorldPosition(); np = V4(q.x, q.y, q.z + 0.9) end)
                            pcall(function() dead = npc:IsDead() end)
                            if np and not dead and SegDist(w.last, p, np) < I.radius[w.o.kind] then
                                w.hit[key] = true
                                Damage(npc, (sp - I.min_speed) * I.dmg[w.o.kind], string.format("struck by a thrown %s at %.0f m/s:", w.o.kind, sp))
                                Ragdoll(npc)
                                pending[#pending + 1] = {h = {obj = npc, kind = "npc", m = 75}, imp = mul(v, 75 * I.push), frames = 2}
                            end
                        end
                    end
                end
                w.sp = sp
            end
            w.last = p or w.last
            if not p then w.last = ThrownPos(w.o) end
        end
    end
end

local function Update(dt)
    clock = clock + dt
    if hud.t > 0 then hud.t = hud.t - dt end
    for i = #flights, 1, -1 do
        local okf, done = pcall(Fly, flights[i], dt)
        if not okf then Log("flight failed: %s", tostring(done)) end
        if not okf or done then table.remove(flights, i) end
    end
    local player = Game.GetPlayer()
    if player then
        local eq = GunEquipped(player)
        if eq ~= gun_equipped then
            gun_equipped = eq
            Log("gravity gun %s", eq and "in hands" or "put away")

            Sound(eq and "gravgun_claws_open" or "gravgun_off")
            if not eq then Drop(); StopPull(); FxDespawn() end
        end
        if gun_equipped then
            local o, tgt = pulling or holding, nil
            if o then pcall(function() tgt = Centre(o) end) end
            local oke, erre = pcall(FxTick, dt, player, tgt, pulling ~= nil)
            if not oke then Warn("effects", "effects failed: %s", tostring(erre)) end
            local okw, errw = pcall(ClawTick, player, pulling ~= nil or holding ~= nil)
            if not okw then Warn("clawtick", "claws failed: %s", tostring(errw)) end
            local okv, errv = pcall(ApplyView, player, dt, false)
            if not okv and not fx.warned.applyview then fx.warned.applyview = true; Log("view failed: %s", tostring(errv)) end
        end
    end
    for i = #checks, 1, -1 do
        local k = checks[i]
        k.frames = k.frames - 1
        if k.frames <= 0 then
            table.remove(checks, i)
            local got = nil
            pcall(function() local lv = k.o.obj:GetLinearVelocity(); got = V4(lv.x, lv.y, lv.z) end)
            local want = len(k.v)
            if want > 1.0 and (not got or len(got) < 0.3 * want) then
                pcall(function() k.o.p = k.o.obj:GetWorldPosition() end)
                flights[#flights + 1] = {h = k.o, p = k.o.p, v = k.v, t = 0, yaw = 0, spin = k.spin, brake = true}
                Log("car impulse did not take (%s of %.1f m/s): flying it instead", got and string.format("%.1f", len(got)) or "?", want)
            else
                pcall(function() k.o.obj:ForceBrakesFor(CFG.car_brake) end)
                Log("car impulse took: %s m/s (wanted %.1f)", got and fmt(got) or "?", want)
            end
        end
    end
    for i = #pending, 1, -1 do
        local p = pending[i]
        p.frames = p.frames - 1
        if p.frames <= 0 then
            table.remove(pending, i)
            local okp, how = pcall(function() return Impulse(p.h, p.imp, Position(p.h), p.off) end)
            Log("delayed impulse %s via %s", fmt(p.imp), okp and tostring(how) or ("failed: " .. tostring(how)))
        end
    end
    -- any weapon taken in hands is dumped (the gun, the tests, a plain Igla to compare)
    if player then
        local rec = nil
        pcall(function()
            local w = Game.GetTransactionSystem():GetItemInSlot(player, TweakDBID.new("AttachmentSlots.WeaponRight"))
            if w then rec = TDBID.ToStringDEBUG(w:GetItemID().id) end
        end)
        if rec ~= last_weapon then
            last_weapon = rec
            if rec then Log("in hands: %s", rec); pending_dump = 30 end
        end
    end
    if pending_dump then
        pending_dump = pending_dump - 1
        if pending_dump <= 0 then
            pending_dump = nil
            local okd, errd = pcall(DumpWeapon, player)
            if not okd then Log("dump failed: %s", tostring(errd)) end
        end
    end
    if dt <= 0 then return end
    pcall(HealthChecks, dt)
    local oki, erri = pcall(ImpactTick, dt)
    if not oki then Warn("impacttick", "impact failed: %s", tostring(erri)) end
    if pulling then
        if not Alive(pulling) then pulling = nil
        else
            local ok, err = pcall(Pull, pulling, dt)
            if not ok then Log("pull failed: %s", tostring(err)); pulling = nil end
        end
    end
    if holding then
        if not Alive(holding) then holding = nil; Sound("gravgun_hold", true)
        else
            local ok, err = pcall(Hold, holding, dt)
            if not ok then Log("hold failed: %s", tostring(err)); holding = nil; Sound("gravgun_hold", true) end
        end
    end
end

-- ---------------------------------------------------------------- the gun's input and its blocked shooting/aiming
local function OnPlayerAction(action)
    if not gun_equipped then return end
    local name = Game.NameToString(ListenerAction.GetName(action))
    local t = ListenerAction.GetType(action)
    local pressed, released = t == gameinputActionType.BUTTON_PRESSED, t == gameinputActionType.BUTTON_RELEASED
    if name == "RangedAttack" and pressed then Primary()
    elseif name == "CameraAim" then
        if pressed then SecondaryDown() elseif released then SecondaryUp() end
    end
end

local function BlockWhileEquipped(class, method)
    local ok, err = pcall(function()
        Override(class, method, function(this, stateContext, scriptInterface, wrapped)
            if gun_equipped then return false end
            return wrapped(stateContext, scriptInterface)
        end)
    end)
    Log("block %s.%s while the gun is in hands: %s", class, method, ok and "ok" or tostring(err))
end

registerForEvent("onInit", function()
    Log("gravgun loaded (CET %s)", tostring(GetVersion and GetVersion() or "?"))
    gun_ready = MakeGun()
    LoadTune()
    local oka, erra = pcall(function()
        Observe("EntityBuilder", "OnAssemble", function(_, event)
            if not fx.idkey or not event then return end
            local e = nil
            pcall(function() e = event:GetEntity() end)
            if e then FxAssemble(e) end
        end)
    end)
    Log("fx assemble hook: %s", oka and "ok" or tostring(erra))
    -- the gun never shoots or aims: every trigger mode's decision says no while it is in hands
    for _, c in ipairs({"SemiAutoDecisions", "FullAutoDecisions", "BurstDecisions", "ChargeDecisions",
                        "WindupDecisions", "LockDecisions"}) do
        BlockWhileEquipped(c, "EnterCondition")
    end
    BlockWhileEquipped("AimingStateDecisions", "EnterCondition")
    -- (run 6.17) no reload either (R played the Igla's reload), and no ammo counter: the HUD's own check
    BlockWhileEquipped("ReloadDecisions", "EnterCondition")
    local okh, errh = pcall(function()
        Override("WeaponRosterGameController", "ShouldHideAmmoCount", function(this, ...)
            local args = {...}
            local wrapped = args[#args]
            local p = Game.GetPlayer()
            if p and GunEquipped(p) then return true end
            return wrapped(unpack(args, 1, #args - 1))
        end)
    end)
    Log("hide the ammo counter while the gun is in hands: %s", okh and "ok" or tostring(errh))
    -- (run 6.19, owner: 'when sprinting the gun turns sideways - unnatural') the sprint keeps the gun raised: the
    -- game's own sprint-animation block (SprintEvents.ApplySprintAnimBlock -> AnimFeature WeaponSprintBlock, what it
    -- uses for weapons that shoot while sprinting) is forced on while the gun is in hands, also every sprint frame
    local sprint_logged = false
    local oks, errs = pcall(function()
        -- (run 6.20 log: 'ApplySprintAnimBlock requires 1 parameter' - it takes only scriptInterface and applies the
        -- state's own flag m_sprintAnimBlocked; so the flag is set, then the block applied)
        Override("SprintEvents", "ApplySprintAnimBlock", function(this, scriptInterface, wrapped)
            local p = Game.GetPlayer()
            if p and GunEquipped(p) then pcall(function() this.m_sprintAnimBlocked = true end) end
            return wrapped(scriptInterface)
        end)
        Observe("SprintEvents", "OnUpdate", function(this, timeDelta, stateContext, scriptInterface)
            if not gun_equipped then return end
            local ok, err = pcall(function()
                this.m_sprintAnimBlocked = true
                this:ApplySprintAnimBlock(scriptInterface)
            end)
            if not sprint_logged then
                sprint_logged = true
                local flag = "?"
                pcall(function() flag = tostring(this.m_sprintAnimBlocked) end)
                Log("sprint: weapon pose block %s (flag %s)", ok and "applied" or ("failed: " .. tostring(err)), flag)
            end
        end)
    end)
    Log("keep the gun raised while sprinting: %s", oks and "ok" or tostring(errs))
    local ok, err = pcall(function()
        Observe("PlayerPuppet", "OnAction", function(this, action, consumer)
            local okA, errA = pcall(OnPlayerAction, action)
            if not okA then Log("action failed: %s", tostring(errA)) end
        end)
    end)
    Log("input hook: %s", ok and "ok" or tostring(err))
end)

registerForEvent("onUpdate", function(dt)
    -- the gift: 3 s after a player appears (a load, also after "Reload all mods"), if V has no gun
    -- (run 3: the OnGameAttached hook never fired, nothing was given)
    local player = Game.GetPlayer()
    local pid = nil   -- CET hands out a new wrapper every call: compare the entity id, not the object
    if player then pcall(function() pid = tostring(player:GetEntityID().hash) end) end
    if pid ~= gift.player then
        gift.player, gift.t, gift.done, gift.tick, gift.last_n, gift.stable = pid, 0, false, 0, -1, 0
        FxReset()   -- a new player (a load): the effects entity of the old one is gone
    end
    if player and not gift.done then
        gift.t, gift.tick = gift.t + dt, gift.tick + dt
        if gift.tick >= 1 then
            gift.tick = 0
            local nitems = -1
            pcall(function() local _, l = Game.GetTransactionSystem():GetItemList(player); nitems = #(l or {}) end)
            if nitems == gift.last_n and nitems > 0 then gift.stable = gift.stable + 1 else gift.stable = 0 end
            gift.last_n = nitems
            if gift.t > 6 and gift.stable >= 3 then
                gift.done = true
                if gun_ready and not HasGun(player) then GiveGun()
                else Log("gift: %s (%d items)", gun_ready and "V already has the gun" or "no gun record", nitems) end
            end
        end
    end
    Update(dt)
end)

-- the tuning window (CET overlay open): the view offset and the effect strengths, live; "Save" writes tune.lua
local function TuneWindow()
    local v, fo = TUNE.view, TUNE.force
    local moved = false
    if ImGui.Begin("Gravity gun") then
        ImGui.Text("Position in hands, cm")
        for _, it in ipairs({{"y", "forward / back"}, {"x", "right / left"}, {"z", "up / down"}}) do
            local val, used = ImGui.SliderFloat(it[2], v[it[1]], -20, 20, "%.1f")
            if used then v[it[1]] = val; moved = true end
        end
        ImGui.Text("If the gun does not move, switch:")
        for i, n in ipairs({"move the gun mesh", "move the rig"}) do
            if i > 1 then ImGui.SameLine() end
            if ImGui.RadioButton(n, v.target == i) then v.target = i; moved = true end
        end
        if ImGui.Button("Reset position") then v.x, v.y, v.z = 0, 0, 0; moved = true end
        ImGui.Separator()
        ImGui.Text("Forces, % (speed for a 75 kg person / a 1500 kg car)")
        for _, it in ipairs({{"punt_npc", "push a person", "npc", false, 75}, {"launch_npc", "throw a held person", "npc", true, 75},
                             {"punt_vehicle", "push a car", "vehicle", false, 1500}, {"launch_vehicle", "throw a held car", "vehicle", true, 1500}}) do
            local val, used = ImGui.SliderInt(it[2], math.floor(fo[it[1]]), 20, 300)
            if used then fo[it[1]] = val end
            local sp = (it[4] and LaunchSpeed(it[5]) or PuntSpeed(it[3], it[5])) * ForceScale(it[3], it[4])
            ImGui.SameLine(); ImGui.Text(string.format("%.0f m/s", sp))
        end
        if ImGui.Button("Reset forces") then for k in pairs(fo) do fo[k] = 100 end end
        ImGui.Separator()
        if ImGui.Button("Save") then SaveTune(); Hud("gravity gun settings saved", 2) end
        local p = Game.GetPlayer()
        local n = p and #GunItems(p) or 0
        if n > 1 then
            ImGui.Text(string.format("Gravity guns in the inventory: %d", n))
            if ImGui.Button("Remove the extra guns (keep one)") then RemoveExtraGuns() end
        end
    end
    ImGui.End()
    if moved then
        local player = Game.GetPlayer()
        if player then pcall(ApplyView, player, 0, true) end
    end
end

registerForEvent("onShutdown", function() FxDespawn() end)
registerForEvent("onOverlayOpen", function() fx.overlay = true end)
registerForEvent("onOverlayClose", function() fx.overlay = false end)

registerForEvent("onDraw", function()
    if fx.overlay then
        local ok, err = pcall(TuneWindow)
        if not ok and not fx.warned.window then fx.warned.window = true; Log("tuning window failed: %s", tostring(err)) end
    end
    if hud.t <= 0 and not holding and not pulling then return end
    pcall(function()
        ImGui.SetNextWindowPos(20, 300)
        if ImGui.Begin("gravgun", true, ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text(holding and ("GRAVGUN: holding " .. holding.kind)
                or (pulling and ("GRAVGUN: pulling " .. pulling.kind)) or ("GRAVGUN: " .. hud.text))
        end
        ImGui.End()
    end)
end)

registerInput("gravgun_grab", "Pull / cancel / drop", function(down) if down then SecondaryDown() else SecondaryUp() end end)
registerInput("gravgun_punt", "Punt / launch", function(down) if down then Primary() end end)
registerHotkey("gravgun_give", "Give the gravity gun", GiveGun)
