TOOL.Category = "Utility"
TOOL.Name = "#Action Recorder"

if CLIENT then
    language.Add("tool.actionrecorder.name", "Action Recorder")
    language.Add("tool.actionrecorder.desc", "Record and playback any movements")
    language.Add("tool.actionrecorder.0", "Left click: Enable/Disable recording | Right click: Place playback box / update settings")
end

if SERVER then
    CreateConVar("actionrecorder_playbackspeed", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_loop", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_playbacktype", "absolute", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_model", "models/dav0r/camera.mdl", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_boxid", "Box", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_globalmode", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_soundpath", "buttons/button1.wav", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_easing", "Linear", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_easing_amplitude", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_easing_frequency", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_easing_invert", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_easing_offset", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
else
    CreateClientConVar("actionrecorder_playbackspeed", "1", true, true)
    CreateClientConVar("actionrecorder_loop", "0", true, true)
    CreateClientConVar("actionrecorder_playbacktype", "absolute", true, true)
    CreateClientConVar("actionrecorder_model", "models/dav0r/camera.mdl", true, true)
    CreateClientConVar("actionrecorder_boxid", "Box", true, true)
    CreateClientConVar("actionrecorder_globalmode", "0", true, true)
    CreateClientConVar("actionrecorder_key", "", true, true)
    CreateClientConVar("actionrecorder_soundpath", "buttons/button1.wav", true, true)
    CreateClientConVar("actionrecorder_easing", "Linear", true, true)
    CreateClientConVar("actionrecorder_easing_amplitude", "1", true, true)
    CreateClientConVar("actionrecorder_easing_frequency", "1", true, true)
    CreateClientConVar("actionrecorder_easing_invert", "0", true, true)
    CreateClientConVar("actionrecorder_easing_offset", "0", true, true)
end

local function vectorsDifferent(a, b)
    return not a or not b or a.x ~= b.x or a.y ~= b.y or a.z ~= b.z
end
local function anglesDifferent(a, b)
    return not a or not b or a.p ~= b.p or a.y ~= b.y or a.r ~= b.r
end

local function StopPropRecording(ply, prop)
    if not IsValid(prop) then return end
    prop.ActionRecorder_Recording = false
    timer.Remove("ActionRecorder_Prop_"..(IsValid(ply) and ply:EntIndex() or 0).."_"..prop:EntIndex())
end

local function IsPropControlledByOtherBox(prop, myBoxID)
    return ActionRecorder.ActivePlaybacks and ActionRecorder.ActivePlaybacks[prop:EntIndex()] ~= nil
end

local function StartPropRecording(ply, prop, boxid)
    if prop.ActionRecorder_Recording then return end

    ply.ActionRecordData = ply.ActionRecordData or {}
    local id = prop:EntIndex()
    ply.ActionRecordData[id] = {}
    prop.ActionRecorder_Recording = true
    local timerName = "ActionRecorder_Prop_"..ply:EntIndex().."_"..id

    timer.Create(timerName, 0.02, 0, function()
        if not IsValid(prop) or not IsValid(ply) or not ply.ActionRecorderEnabled or not ply.ActionRecordData then
            StopPropRecording(ply, prop)
            return
        end

        if not ply.ActionRecordData[id] then return end

        local last = ply.ActionRecordData[id][#ply.ActionRecordData[id]]
        local cur = {
            pos = prop:GetPos(),
            ang = prop:GetAngles(),
            time = CurTime(),
            material = prop:GetMaterial(),
            color = prop:GetColor(),
            renderfx = prop:GetRenderFX(),
            rendermode = prop:GetRenderMode(),
            skin = prop:GetSkin(),
            bodygroups = (function()
                local t = {}
                for k,v in pairs(prop:GetBodyGroups() or {}) do
                    t[v.id] = prop:GetBodygroup(v.id)
                end
                return t
            end)()
        }

        local changed = false
        if not last or vectorsDifferent(last.pos, cur.pos) or anglesDifferent(last.ang, cur.ang)
            or last.material ~= cur.material
            or last.skin ~= cur.skin
            or last.rendermode ~= cur.rendermode
            or last.renderfx ~= cur.renderfx then
            changed = true
        elseif last.color and cur.color and (last.color.r ~= cur.color.r or last.color.g ~= cur.color.g or last.color.b ~= cur.color.b or last.color.a ~= cur.color.a) then
            changed = true
        else
            for id, val in pairs(cur.bodygroups) do
                if not last.bodygroups or last.bodygroups[id] ~= val then
                    changed = true
                    break
                end
            end
        end

        if changed then
            table.insert(ply.ActionRecordData[id], cur)
        end
    end)
end

hook.Add("EntityRemoved", "ActionRecorder_EntityRemoved", function(ent)
    if ent.ActionRecorder_Recording then
        StopPropRecording(nil, ent)
    end
end)

hook.Add("Think", "ActionRecorder_Think", function()
    for _, ply in pairs(player.GetAll()) do
        if ply.ActionRecorderEnabled then
            local globalMode = GetConVar("actionrecorder_globalmode"):GetBool()
            local boxid
            if globalMode and ply:IsAdmin() then
                boxid = GetConVar("actionrecorder_boxid"):GetString() or "Box"
            else
                boxid = ply:GetInfo("actionrecorder_boxid") or "Box"
            end
            for _, ent in pairs(ents.GetAll()) do
                if IsValid(ent) and not ent:IsPlayer() and not ent.ActionRecorder_Recording then
                    if ent.GetCreator and ent:GetCreator() == ply and not IsPropControlledByOtherBox(ent, boxid) then
                        local phys = ent:GetPhysicsObject()
                        if IsValid(phys) then
                            StartPropRecording(ply, ent, boxid)
                        end
                    end
                end
            end
        end
    end
end)

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    ply.ActionRecorderEnabled = not ply.ActionRecorderEnabled

    local globalMode = GetConVar("actionrecorder_globalmode"):GetBool()
    local boxid
    if globalMode and ply:IsAdmin() then
        boxid = GetConVar("actionrecorder_boxid"):GetString() or "Box"
    else
        boxid = ply:GetInfo("actionrecorder_boxid") or "Box"
    end

    if ply.ActionRecorderEnabled then
        ply.ActionRecordData = {}

        for _, ent in pairs(ents.GetAll()) do
            if IsValid(ent) and not ent:IsPlayer() then
                if ent.GetCreator and ent:GetCreator() == ply and not IsPropControlledByOtherBox(ent, boxid) then
                    local phys = ent:GetPhysicsObject()
                    if IsValid(phys) then
                        StartPropRecording(ply, ent, boxid)
                    end
                end
            end
        end

        ply:ChatPrint("Recording enabled! Only your props will record (and not props already controlled by other boxes).")
    else
        ply:ChatPrint("Recording disabled! Right click to place playback box / update settings.")
    end
    return true
end

function TOOL:RightClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    local globalMode = GetConVar("actionrecorder_globalmode"):GetBool()
    local speed, loop, playbackType, model, boxid, key, soundpath, easing, easing_amplitude, easing_frequency, easing_invert, easing_offset

    if globalMode and ply:IsAdmin() then
        speed = tonumber(GetConVar("actionrecorder_playbackspeed"):GetString()) or 1
        loop = GetConVar("actionrecorder_loop"):GetInt()
        playbackType = GetConVar("actionrecorder_playbacktype"):GetString() or "absolute"
        model = GetConVar("actionrecorder_model"):GetString() or "models/dav0r/camera.mdl"
        boxid = GetConVar("actionrecorder_boxid"):GetString() or "Box"
        key = GetConVar("actionrecorder_key"):GetInt()
        soundpath = GetConVar("actionrecorder_soundpath"):GetString()
        easing = GetConVar("actionrecorder_easing"):GetString() or "Linear"
        easing_amplitude = GetConVar("actionrecorder_easing_amplitude"):GetFloat()
        easing_frequency = GetConVar("actionrecorder_easing_frequency"):GetFloat()
        easing_invert = GetConVar("actionrecorder_easing_invert"):GetBool()
        easing_offset = GetConVar("actionrecorder_easing_offset"):GetFloat()
    else
        speed = ply:GetInfoNum("actionrecorder_playbackspeed", 1)
        loop = ply:GetInfoNum("actionrecorder_loop", 0)
        playbackType = ply:GetInfo("actionrecorder_playbacktype") or "absolute"
        model = ply:GetInfo("actionrecorder_model") or "models/dav0r/camera.mdl"
        boxid = ply:GetInfo("actionrecorder_boxid") or "Box"
        key = ply:GetInfoNum("actionrecorder_key", 5)
        soundpath = ply:GetInfo("actionrecorder_soundpath")
        easing = ply:GetInfo("actionrecorder_easing") or "Linear"
        easing_amplitude = ply:GetInfoNum("actionrecorder_easing_amplitude", 1)
        easing_frequency = ply:GetInfoNum("actionrecorder_easing_frequency", 1)
        easing_invert = ply:GetInfoNum("actionrecorder_easing_invert", 0) == 1
        easing_offset = ply:GetInfoNum("actionrecorder_easing_offset", 0)
    end

    local updated = false
    for _, ent in pairs(ents.FindByClass("action_playback_box")) do
        local entBoxID = ent.BoxID or (ent.GetNWString and ent:GetNWString("BoxID", ""))
        if IsValid(ent) and entBoxID == boxid then
            ent:UpdateSettings(speed, loop, playbackType, model, boxid, soundpath, easing, easing_amplitude, easing_frequency, easing_invert, easing_offset)
            ent.NumpadKey = key
            if SERVER then ent:SetupNumpad() end
            updated = true
        end
    end

    if updated then
        ply:ChatPrint("Playback box(es) with BoxID '"..boxid.."' updated with new settings!")
        return true
    end

    if not ply.ActionRecordData or table.Count(ply.ActionRecordData) == 0 then
        ply:ChatPrint("No recording found!")
        return false
    end

    local ent = ents.Create("action_playback_box")
    if not IsValid(ent) then return false end
    ent:SetPos(trace.HitPos + Vector(0,0,10))
    ent:Spawn()

    ent:SetPlaybackData(ply.ActionRecordData)
    ent:SetPlaybackSettings(speed, loop, playbackType, easing, easing_amplitude, easing_frequency, easing_invert, easing_offset)
    ent:SetModelPath(model)
    ent:SetBoxID(boxid)
    ent:SetOwnerName(ply:Nick() or "Unknown")
    ent.NumpadKey = key
    ent:SetSoundPath(soundpath)
    if SERVER then ent:SetupNumpad() end

    undo.Create("Action Playback Box")
        undo.AddEntity(ent)
        undo.SetPlayer(ply)
    undo.Finish()

    ply:ChatPrint("Playback box placed! Press E on it to start playback.")
    ply.ActionRecordData = nil
    return true
end

if CLIENT then
    include("vgui/action_recorder_graph_editor.lua")
end

function TOOL.BuildCPanel(panel)
    panel:Help("Playback Speed (negative = reverse)")
    panel:NumSlider("Playback Speed", "actionrecorder_playbackspeed", -500, 500, 2):SetDecimals(2)
    panel:Help("Loop Mode")
    local loop_combo = panel:ComboBox("Loop Mode", "actionrecorder_loop")
    loop_combo:AddChoice("No Loop", 0, true)
    loop_combo:AddChoice("Loop", 1)
    loop_combo:AddChoice("Ping-Pong", 2)
    panel:Help("Playback Type")
    local combo = panel:ComboBox("Playback Type", "actionrecorder_playbacktype")
    combo:AddChoice("absolute", "absolute", true)
    combo:AddChoice("relative", "relative")

    panel:Help("Easing")
    local easing_combo = panel:ComboBox("Easing", "actionrecorder_easing")
    for name, _ in pairs(ActionRecorder.EasingFunctions) do
        easing_combo:AddChoice(name)
    end

    local custom_easing_button = panel:Button("Edit Custom Easing", "actionrecorder_edit_custom_easing")
    custom_easing_button:SetSize(150, 20)
    custom_easing_button:SetImage("icon16/page_white_edit.png")
    custom_easing_button.DoClick = function()
        vgui.Create("ActionRecorderGraphEditor")
    end

    panel:Help("Model Path")
    panel:TextEntry("Model", "actionrecorder_model")
    panel:Help("Playback Box ID / Name")
    panel:TextEntry("Box ID", "actionrecorder_boxid")
    panel:Help("Activation Sound")
    panel:TextEntry("Sound Path", "actionrecorder_soundpath")
    panel:Help("Keybind")
    panel:KeyBinder("Playback Key", "actionrecorder_key")

    panel:Help("Easing Amplitude")
    panel:NumSlider("Easing Amplitude", "actionrecorder_easing_amplitude", 0, 10, 2)
    panel:Help("Easing Frequency")
    panel:NumSlider("Easing Frequency", "actionrecorder_easing_frequency", 0, 10, 2)
    panel:Help("Easing Invert")
    panel:CheckBox("Invert Easing", "actionrecorder_easing_invert")
    panel:Help("Easing Offset")
    panel:NumSlider("Easing Offset", "actionrecorder_easing_offset", -1, 1, 2)
end

function TOOL:GetSetConVars(ply)
    local globalMode = GetConVar("actionrecorder_globalmode"):GetBool()
    local cvars = {
        "actionrecorder_playbackspeed",
        "actionrecorder_loop",
        "actionrecorder_playbacktype",
        "actionrecorder_model",
        "actionrecorder_boxid",
        "actionrecorder_key",
        "actionrecorder_soundpath",
        "actionrecorder_easing",
        "actionrecorder_easing_amplitude",
        "actionrecorder_easing_frequency",
        "actionrecorder_easing_invert",
        "actionrecorder_easing_offset"
    }

    local settings = {}
    for _, cvar in ipairs(cvars) do
        if globalMode and ply:IsAdmin() then
            settings[cvar] = GetConVar(cvar):GetString()
        else
            settings[cvar] = ply:GetInfo(cvar)
        end
    end
    return settings
end

function TOOL:ApplyConVars(ply, settings)
    local globalMode = GetConVar("actionrecorder_globalmode"):GetBool()
    for cvar, val in pairs(settings) do
        if globalMode and ply:IsAdmin() then
            RunConsoleCommand(cvar, val)
        else
            ply:SetInfo(cvar, val)
        end
    end
end

function TOOL:Holster()
    if CLIENT then
        if IsValid(self.CustomEasingEditor) then
            self.CustomEasingEditor:Close()
        end
    end
end

local function GetEasingFunction(name)
    return ActionRecorder.EasingFunctions[name]
end

if CLIENT then
    ActionRecorder.EasingFunctions = ActionRecorder.EasingFunctions or {}
    ActionRecorder.EasingFunctions["Linear"] = function(t, amp, freq, inv, offset) return t end
    ActionRecorder.EasingFunctions["Sine"] = function(t, amp, freq, inv, offset) return math.sin(t * math.pi * freq + offset) * amp end
    ActionRecorder.EasingFunctions["Quadratic"] = function(t, amp, freq, inv, offset) return t*t * amp end
    ActionRecorder.EasingFunctions["Cubic"] = function(t, amp, freq, inv, offset) return t*t*t * amp end
    ActionRecorder.EasingFunctions["Quartic"] = function(t, amp, freq, inv, offset) return t*t*t*t * amp end
    ActionRecorder.EasingFunctions["Quintic"] = function(t, amp, freq, inv, offset) return t*t*t*t*t * amp end
    ActionRecorder.EasingFunctions["Exponential"] = function(t, amp, freq, inv, offset) return math.pow(2, 10 * (t - 1)) * amp end
    ActionRecorder.EasingFunctions["Circular"] = function(t, amp, freq, inv, offset) return math.sqrt(1 - (t-1)*(t-1)) * amp end
    ActionRecorder.EasingFunctions["Elastic"] = function(t, amp, freq, inv, offset)
        if t == 0 or t == 1 then return t end
        local p = .3
        local s = p / 4
        return amp * math.pow(2, -10 * t) * math.sin((t - s) * (2 * math.pi) / p) + 1
    end
    ActionRecorder.EasingFunctions["Back"] = function(t, amp, freq, inv, offset)
        local s = 1.70158
        return amp * (t*t*((s+1)*t - s))
    end
    ActionRecorder.EasingFunctions["Bounce"] = function(t, amp, freq, inv, offset)
        if t < (1/2.75) then
            return amp * (7.5625*t*t)
        elseif t < (2/2.75) then
            t = t - (1.5/2.75)
            return amp * (7.5625*t*t + .75)
        elseif t < (2.5/2.75) then
            t = t - (2.25/2.75)
            return amp * (7.5625*t*t + .9375)
        else
            t = t - (2.625/2.75)
            return amp * (7.5625*t*t + .984375)
        end
    end
    ActionRecorder.EasingFunctions["Custom"] = function(t, amp, freq, inv, offset)
        local points = ActionRecorder.CustomEasingPoints or {{x = 0, y = 0}, {x = 1, y = 1}}

        -- Ensure points are sorted by x (should already be from VGUI, but good to be safe)
        table.sort(points, function(a, b) return a.x < b.x end)

        -- Handle edge cases for t outside the defined range of points
        if t <= points[1].x then
            return points[1].y * amp
        end
        if t >= points[#points].x then
            return points[#points].y * amp
        end

        local y_val = 0
        for i = 1, #points - 1 do
            local p1 = points[i]
            local p2 = points[i+1]

            if t >= p1.x and t <= p2.x then
                local range_x = p2.x - p1.x
                local range_y = p2.y - p1.y
                local normalized_x = (t - p1.x) / range_x
                y_val = p1.y + normalized_x * range_y
                break
            end
        end
        return y_val * amp
    end
end