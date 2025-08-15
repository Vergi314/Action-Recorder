TOOL.Category = "Construction"
TOOL.Name = "#Action Recorder"
TOOL.Mode = "actionrecorder"

if CLIENT then
    language.Add("tool.actionrecorder.name", "Action Recorder")
    language.Add("tool.actionrecorder.desc", "Record and playback any movements")
    language.Add("tool.actionrecorder.0", "Left click: Enable/Disable recording | Right click: Place playback box / update settings")
end

if SERVER then
    CreateConVar("actionrecorder_playbackspeed", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_loop", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
	CreateConVar("actionrecorder_freezeonend", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED})
    CreateConVar("actionrecorder_playbacktype", "absolute", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_model", "models/dav0r/camera.mdl", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_boxid", "Box", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_globalmode", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_soundpath", "buttons/button1.wav", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_easing", "None", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_easing_amplitude", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_easing_frequency", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_easing_invert", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_easing_offset", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_labelcolor_r", "255", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
	CreateConVar("actionrecorder_labelcolor_g", "255", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
	CreateConVar("actionrecorder_labelcolor_b", "255", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
    CreateConVar("actionrecorder_labelcolor_a", "255", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
	CreateConVar("actionrecorder_labelcolor_rainbow", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
	CreateConVar("actionrecorder_reverseplayback", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED })
else
    CreateClientConVar("actionrecorder_playbackspeed", "1", true, true)
    CreateClientConVar("actionrecorder_loop", "0", true, true)
	CreateClientConVar("actionrecorder_freezeonend", "0", true, true)
    CreateClientConVar("actionrecorder_playbacktype", "absolute", true, true)
    CreateClientConVar("actionrecorder_model", "models/dav0r/camera.mdl", true, true)
    CreateClientConVar("actionrecorder_boxid", "Box", true, true)
    CreateClientConVar("actionrecorder_globalmode", "0", true, true)
    CreateClientConVar("actionrecorder_key", "", true, true)
    CreateClientConVar("actionrecorder_soundpath", "buttons/button1.wav", true, true)
    CreateClientConVar("actionrecorder_easing", "None", true, true)
    CreateClientConVar("actionrecorder_easing_amplitude", "1", true, true)
    CreateClientConVar("actionrecorder_easing_frequency", "1", true, true)
    CreateClientConVar("actionrecorder_easing_invert", "0", true, true)
    CreateClientConVar("actionrecorder_easing_offset", "0", true, true)
	CreateClientConVar("actionrecorder_labelcolor_r", "255", true, false)
    CreateClientConVar("actionrecorder_labelcolor_g", "255", true, false)
    CreateClientConVar("actionrecorder_labelcolor_b", "255", true, false)
    CreateClientConVar("actionrecorder_labelcolor_a", "255", true, false)
	CreateClientConVar("actionrecorder_labelcolor_rainbow", "0", true, false)
	CreateClientConVar("actionrecorder_reverseplayback", "0", true, true)
end

if SERVER then
    util.AddNetworkString("ActionRecorder_PlayStartSound")
    util.AddNetworkString("ActionRecorder_PlayLoopSound")
    util.AddNetworkString("ActionRecorder_PlayStopSound")
    util.AddNetworkString("ActionRecorder_StopLoopSound")
    util.AddNetworkString("ActionRecorderNotify")
    util.AddNetworkString("ActionRecorder_FlashEffect")
	util.AddNetworkString("ActionRecorder_UpdateLabel")

local PlayerLabelColors = {}

net.Receive("ActionRecorder_UpdateLabel", function(len, ply)
    if not IsValid(ply) then return end
    local r = net.ReadUInt(8)
    local g = net.ReadUInt(8)
    local b = net.ReadUInt(8)
    local a = net.ReadUInt(8)
    local rainbow = net.ReadBool()

    PlayerLabelColors[ply] = {r=r, g=g, b=b, a=a, rainbow=rainbow}
    
    
end)

function ActionRecorder_GetLabelColorForPlayer(ply)
    return PlayerLabelColors[ply] or {r = 255, g = 255, b = 255, a = 255, rainbow = false}
end

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

    local phys = prop:GetPhysicsObject()
    if IsValid(phys) and prop.ActionRecorder_WasFrozen then
        phys:EnableMotion(false)
    end
    prop.ActionRecorder_WasFrozen = nil
end

local function IsPropControlledByOtherBox(prop, myBoxID)
    return ActionRecorder.ActivePlaybacks and ActionRecorder.ActivePlaybacks[prop:EntIndex()] ~= nil
end

local function StartPropRecording(ply, prop, boxid)
    if prop.ActionRecorder_Recording then return end

    ply.ActionRecordData = ply.ActionRecordData or {}
    ply.ActionRecordEntsData = ply.ActionRecordEntsData or {}
    local id = prop:EntIndex()
    ply.ActionRecordData[id] = {}
    ply.ActionRecordEntsData[id] = {
        model = prop:GetModel(),
        class = prop:GetClass()
    }
    prop.ActionRecorder_Recording = true
    local timerName = "ActionRecorder_Prop_"..ply:EntIndex().."_"..id

    -- Add initial frame
    local cur = {
        pos = prop:GetPos(),
        ang = prop:GetAngles(),
        time = CurTime(),
        material = prop:GetMaterial(),
        color = prop:GetColor(),
        renderfx = prop:GetRenderFX(),
        rendermode = prop:GetRenderMode(),
        skin = prop:GetSkin(),
        ignited = prop:IsOnFire(),
        collisiongroup = prop:GetCollisionGroup(),
        bodygroups = (function()
            local t = {}
            for k,v in pairs(prop:GetBodyGroups() or {}) do
                t[v.id] = prop:GetBodygroup(v.id)
            end
            return t
        end)()
    }
    table.insert(ply.ActionRecordData[id], cur)

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
            ignited = prop:IsOnFire(),
            collisiongroup = prop:GetCollisionGroup(),
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
            or last.ignited ~= cur.ignited
            or last.collisiongroup ~= cur.collisiongroup
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
                if IsValid(ent) and not ent:IsPlayer() and not ent.ActionRecorder_Recording and not (ply.PreviouslyRecordedEnts and ply.PreviouslyRecordedEnts[ent:EntIndex()]) then
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
    if SERVER then
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

            net.Start("ActionRecorder_PlayStartSound")
            net.Send(ply)

            net.Start("ActionRecorder_PlayLoopSound")
            net.Send(ply)

            net.Start("ActionRecorderNotify")
            net.WriteString("Recording enabled!")
            net.WriteInt(3, 3)
            net.Send(ply)

            ply.ActionRecordData = {}
            ply.ActionRecordEntsData = {}

            for _, ent in pairs(ents.GetAll()) do
                if IsValid(ent) and not ent:IsPlayer() and not (ply.PreviouslyRecordedEnts and ply.PreviouslyRecordedEnts[ent:EntIndex()]) then
                    if ent.GetCreator and ent:GetCreator() == ply and not IsPropControlledByOtherBox(ent, boxid) then
                        local phys = ent:GetPhysicsObject()
                        if IsValid(phys) then
                            StartPropRecording(ply, ent, boxid)
                        end
                    end
                end
            end

            umsg.Start("ActionRecorder_ToggleRecording", ply)
            umsg.Bool(true)
            umsg.End()

            if ply:GetInfoNum("ar_enable_filmgrain", 1) == 1 then
                net.Start("ActionRecorder_FlashEffect")
                net.Send(ply)
            end

        else
            net.Start("ActionRecorder_PlayStopSound")
            net.Send(ply)

            net.Start("ActionRecorder_StopLoopSound")  
            net.Send(ply)

            if ply:GetInfoNum("ar_enable_filmgrain", 1) == 1 then
                net.Start("ActionRecorder_FlashEffect")
                net.Send(ply)
            end

            net.Start("ActionRecorderNotify")
            net.WriteString("Recording disabled! Right click to place playback box / update settings.")
            net.WriteInt(3, 3)
            net.Send(ply)

            umsg.Start("ActionRecorder_ToggleRecording", ply)
            umsg.Bool(false)
            umsg.End()
        end
    end

    return true
end








function TOOL:RightClick(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    local isDedicated = game.IsDedicated()
    local globalMode = GetConVar("actionrecorder_globalmode"):GetBool()

    local speed, loop, playbackType, model, boxid, key, soundpath
    local easing, easing_amplitude, easing_frequency, easing_invert, easing_offset
    local physicsless, freezeonend
    local label_r, label_g, label_b, label_a, label_rainbow
    local reversePlayback

    -- Global settings are only used on a listen server (not dedicated), when global mode is on, and for the host (admin).
    local useGlobalSettings = not isDedicated and globalMode and ply:IsAdmin()

    if useGlobalSettings then
        -- Admin on listen server in global mode uses global settings
        speed = tonumber(GetConVar("actionrecorder_playbackspeed"):GetString()) or 1
        loop = GetConVar("actionrecorder_loop"):GetInt()
        playbackType = GetConVar("actionrecorder_playbacktype"):GetString() or "absolute"
        model = GetConVar("actionrecorder_model"):GetString() or "models/dav0r/camera.mdl"
        boxid = GetConVar("actionrecorder_boxid"):GetString() or "Box"
        soundpath = GetConVar("actionrecorder_soundpath"):GetString()
        easing = GetConVar("actionrecorder_easing"):GetString() or "Linear"
        easing_amplitude = GetConVar("actionrecorder_easing_amplitude"):GetFloat()
        easing_frequency = GetConVar("actionrecorder_easing_frequency"):GetFloat()
        easing_invert = GetConVar("actionrecorder_easing_invert"):GetBool()
        easing_offset = GetConVar("actionrecorder_easing_offset"):GetFloat()
        freezeonend = GetConVar("actionrecorder_freezeonend"):GetBool()
        reversePlayback = GetConVar("actionrecorder_reverseplayback"):GetBool()
    else
        -- Everyone on a dedicated server, or non-admins on a listen server, use their own settings
        speed = ply:GetInfoNum("actionrecorder_playbackspeed", 1)
        loop = ply:GetInfoNum("actionrecorder_loop", 0)
        playbackType = ply:GetInfo("actionrecorder_playbacktype") or "absolute"
        model = ply:GetInfo("actionrecorder_model") or "models/dav0r/camera.mdl"
        boxid = ply:GetInfo("actionrecorder_boxid") or "Box"
        soundpath = ply:GetInfo("actionrecorder_soundpath")
        easing = ply:GetInfo("actionrecorder_easing") or "None"
        easing_amplitude = ply:GetInfoNum("actionrecorder_easing_amplitude", 1)
        easing_frequency = ply:GetInfoNum("actionrecorder_easing_frequency", 1)
        easing_invert = ply:GetInfoNum("actionrecorder_easing_invert", 0) == 1
        easing_offset = ply:GetInfoNum("actionrecorder_easing_offset", 0)
        freezeonend = ply:GetInfoNum("actionrecorder_freezeonend", 0) == 1
        reversePlayback = ply:GetInfoNum("actionrecorder_reverseplayback", 0) == 1
    end

    -- These settings are always per-player
    key = ply:GetInfoNum("actionrecorder_key", 5)
    physicsless = ply:GetInfoNum("ar_physicsless_teleport", 0) == 1

    -- Label color is always per-player
    local labelColor = ActionRecorder_GetLabelColorForPlayer(ply)
    label_r = labelColor.r or 255
    label_g = labelColor.g or 255
    label_b = labelColor.b or 255
    label_a = labelColor.a or 255
    label_rainbow = labelColor.rainbow or false

    
    for _, ent in pairs(ents.FindByClass("action_playback_box")) do
        if IsValid(ent) and ent:GetOwner() == ply and ent.NumpadKey == key and key ~= 0 and ent:GetNWString("BoxID", "") ~= boxid then
            net.Start("ActionRecorderNotify")
            net.WriteString("Keybind already used by another one of your boxes!")
            net.WriteInt(1, 1)
            net.Send(ply)
            return false
        end
    end

    
    local found_box_owned = nil
    for _, ent in pairs(ents.FindByClass("action_playback_box")) do
        local entBoxID = ent.GetNWString and ent:GetNWString("BoxID", "") or (ent.BoxID or "")
        local entOwner = ent.GetOwner and ent:GetOwner() or nil
        if IsValid(ent) and entBoxID == boxid then
            if entOwner ~= ply then
                net.Start("ActionRecorderNotify")
                net.WriteString("BoxID is already in use by another player!")
                net.WriteInt(3, 3)
                net.Send(ply)
                return false
            else
                found_box_owned = ent
            end
        end
    end

    
    if found_box_owned then
        found_box_owned:UpdateSettings(
            speed, loop, playbackType, model, boxid, soundpath,
            easing, easing_amplitude, easing_frequency, easing_invert, easing_offset,
            physicsless, freezeonend, reversePlayback
        )
        found_box_owned.NumpadKey = key
        found_box_owned:SetPhysicslessTeleport(physicsless)
        found_box_owned:SetNWBool("FreezeOnEnd", freezeonend)

        
        found_box_owned:SetNWInt("LabelColorR", label_r)
        found_box_owned:SetNWInt("LabelColorG", label_g)
        found_box_owned:SetNWInt("LabelColorB", label_b)
        found_box_owned:SetNWInt("LabelColorA", label_a)
        found_box_owned:SetNWBool("LabelRainbow", label_rainbow)

        found_box_owned:SetupNumpad()

        net.Start("ActionRecorderNotify")
        net.WriteString("Playback box with BoxID '" .. boxid .. "' updated with new settings!")
        net.WriteInt(3, 3)
        net.Send(ply)
        return true
    end

    
    if not ply.ActionRecordData or table.Count(ply.ActionRecordData) == 0 then
        net.Start("ActionRecorderNotify")
        net.WriteString("No recording found!")
        net.WriteInt(3, 3)
        net.Send(ply)
        return false
    end

    
    local ent = ents.Create("action_playback_box")
    if not IsValid(ent) then return false end

    ent:SetPos(trace.HitPos + Vector(0, 0, 10))
    ent:Spawn()
    ent:SetPlaybackData(ply.ActionRecordData, ply.ActionRecordEntsData)
    ent:SetPlaybackSettings(
        speed, loop, playbackType,
        easing, easing_amplitude, easing_frequency, easing_invert, easing_offset, physicsless, freezeonend, reversePlayback
    )
    ent:SetModelPath(model)
    ent:SetBoxID(boxid)
    ent:SetOwner(ply)
    ent:SetOwnerName(ply:Nick() or "Unknown")
    ent.NumpadKey = key
    ent:SetSoundPath(soundpath)
    ent:SetPhysicslessTeleport(physicsless)
    ent:SetNWBool("FreezeOnEnd", freezeonend)

    
    ent:SetNWInt("LabelColorR", label_r)
    ent:SetNWInt("LabelColorG", label_g)
    ent:SetNWInt("LabelColorB", label_b)
    ent:SetNWInt("LabelColorA", label_a)
    ent:SetNWBool("LabelRainbow", label_rainbow)

    ent:SetupNumpad()

    undo.Create("Action Playback Box")
        undo.AddEntity(ent)
        undo.SetPlayer(ply)
    undo.Finish()

    net.Start("ActionRecorderNotify")
    net.WriteString("Playback box placed! Press E on it to start playback.")
    net.WriteInt(3, 3)
    net.Send(ply)

    -- Store previously recorded entities to prevent re-recording
    ply.PreviouslyRecordedEnts = ply.PreviouslyRecordedEnts or {}
    for id, _ in pairs(ply.ActionRecordData or {}) do
        ply.PreviouslyRecordedEnts[id] = true
    end
    ply.ActionRecordData = nil
    ply.ActionRecordEntsData = nil

    return true
end









if CLIENT then
    include("vgui/action_recorder_graph_editor.lua")

    local isRecording = false

    usermessage.Hook("ActionRecorder_ToggleRecording", function(um)
        isRecording = um:ReadBool()
    end)

    hook.Add("HUDPaint", "ActionRecorder_HUDPaint", function()
        local ply = LocalPlayer()
        if ply:GetTool("actionrecorder") and isRecording then
            if GetConVar("ar_enable_filmgrain"):GetBool() then
                -- Apply film-like effect
                -- Subtle sepia tone
                DrawColorModify({
                    ["$pp_colour_addr"] = 0,
                    ["$pp_colour_addg"] = 0,
                    ["$pp_colour_addb"] = 0,
                    ["$pp_colour_contrast"] = 1.0,
                    ["$pp_colour_brightness"] = 0.0,
                    ["$pp_colour_desaturation"] = 0.05, -- Even more subtle desaturation
                    ["$pp_colour_mulr"] = 1.0,
                    ["$pp_colour_mulg"] = 0.95, -- Less green tint
                    ["$pp_colour_mulb"] = 0.9,  -- Less blue tint
                })

                -- Film grain overlay using noise.vmt
                local noiseMaterial = Material("overlays/noise.vmt")
                if noiseMaterial and not noiseMaterial:IsError() then
                    render.SetMaterial(noiseMaterial)
                    render.DrawScreenQuad()
                end

                -- Additive noise overlay using noiseadd.vmt for enhanced effect
                local noiseAddMaterial = Material("overlays/noiseadd.vmt")
                if noiseAddMaterial and not noiseAddMaterial:IsError() then
                    render.SetMaterial(noiseAddMaterial)
                    render.DrawScreenQuad()
                end
            end

            

            if GetConVar("ar_enable_hud"):GetBool() then
                -- Draw the recording HUD element (on top)
                local material = Material("vgui/action_recorder_hud_rec.png")
                if not material or material:IsError() then return end

                surface.SetDrawColor(255, 255, 255, 255)
                surface.SetMaterial(material)
                surface.DrawTexturedRect(ScrW() - 450, 0, 500, 300)
            end
        end
    end)
end

function TOOL.BuildCPanel(panel)
    local color_red    = Color(222, 33, 16)
    local color_yellow = Color(252, 209, 22)
    local color_blue   = Color(0, 61, 165)

    local function colorHeader(form, col)
        timer.Simple(0, function()
            if not IsValid(form) or not IsValid(form.Header) then return end
            form.Header.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, col)
                
            end
        end)
    end

    local signature = vgui.Create("DImage", panel)
    signature:SetImage("vgui/action_recorder_signature.png")
    signature:SetSize(340, 179)
    signature:Dock(TOP)
    signature:DockMargin(0, -30, 0, -5)
    signature:SetKeepAspect(true)
    panel:AddItem(signature)

    local sectionDividerGeneral = vgui.Create("DPanel", panel)
    sectionDividerGeneral:SetTall(2)
    sectionDividerGeneral:SetBackgroundColor(Color(50, 50, 50, 200))
    sectionDividerGeneral:Dock(TOP)
    sectionDividerGeneral:DockMargin(0, 2, 0, 2)
    panel:AddItem(sectionDividerGeneral)

    
    local generalSettingsForm = vgui.Create("DForm", panel)
    generalSettingsForm:SetName("General Settings")
    generalSettingsForm:Dock(TOP)
    generalSettingsForm:DockMargin(0, 2, 0, 2)
    panel:AddItem(generalSettingsForm)
    colorHeader(generalSettingsForm, color_red)
    generalSettingsForm:NumSlider("Playback Speed", "actionrecorder_playbackspeed", 0, 50, 2):SetDecimals(2)
    generalSettingsForm:CheckBox("Reverse Playback", "actionrecorder_reverseplayback")
    local loop_combo = generalSettingsForm:ComboBox("Loop Mode", "actionrecorder_loop")
    loop_combo:AddChoice("No Loop", 0, true)
    loop_combo:AddChoice("Loop", 1)
    loop_combo:AddChoice("Ping-Pong", 2)
    loop_combo:AddChoice("No Loop (Smooth)", 3)
    loop_combo.OnChange = function(self, index, value, data)
        RunConsoleCommand("actionrecorder_loop", self:GetOptionData(index))
    end
    local combo = generalSettingsForm:ComboBox("Playback Type", "actionrecorder_playbacktype")
    combo:AddChoice("absolute", "absolute", true)
    combo:AddChoice("relative", "relative")
    combo.OnChange = function(self, index, value)
        RunConsoleCommand("actionrecorder_playbacktype", value)
    end
    generalSettingsForm:TextEntry("Model", "actionrecorder_model")
    generalSettingsForm:TextEntry("Playback Box ID", "actionrecorder_boxid")
    generalSettingsForm:TextEntry("Activation Sound", "actionrecorder_soundpath")
	generalSettingsForm:CheckBox("Freeze End(NO LOOP Only)", "actionrecorder_freezeonend")
    generalSettingsForm:CheckBox("Physicsless Teleport", "ar_physicsless_teleport")
    local keyBinder = vgui.Create("DBinder")
    keyBinder:SetConVar("actionrecorder_key")
    generalSettingsForm:AddItem(keyBinder)
	
	local colorPickerButton = vgui.Create("DButton", generalSettingsForm)
    colorPickerButton:SetText("Change Label Color")
    colorPickerButton:SetImage("icon16/color_wheel.png")
    colorPickerButton:SetToolTip("Open color palette to change label color")
    colorPickerButton:SetTall(25)
    colorPickerButton.DoClick = function()
    if not IsValid(MyColorPicker) then
        MyColorPicker = vgui.Create("MyColorPicker")
    end
    MyColorPicker:MakePopup()
    MyColorPicker:Center()
    end
    generalSettingsForm:AddItem(colorPickerButton)

    local sectionDivider = vgui.Create("DPanel", panel)
    sectionDivider:SetTall(2)
    sectionDivider:SetBackgroundColor(Color(50, 50, 50, 200))
    sectionDivider:Dock(TOP)
    sectionDivider:DockMargin(0, 2, 0, 2)
    panel:AddItem(sectionDivider)

    
    local easingSettingsForm = vgui.Create("DForm", panel)
    easingSettingsForm:SetName("Easing Settings")
    easingSettingsForm:Dock(TOP)
    easingSettingsForm:DockMargin(0, 2, 0, 2)
    panel:AddItem(easingSettingsForm)
    colorHeader(easingSettingsForm, color_yellow)
    local easingHelpLabel = vgui.Create("DLabel", easingSettingsForm)
    easingHelpLabel:SetText("Easing is an experimental feature and may not always work as intended.")
    easingHelpLabel:SetTextColor(Color(0, 0, 128))
    easingHelpLabel:SetWrap(true)
    easingSettingsForm:AddItem(easingHelpLabel)
    local easing_combo = easingSettingsForm:ComboBox("Easing", "actionrecorder_easing")
    for name, _ in pairs(ActionRecorder.EasingFunctions) do
        easing_combo:AddChoice(name)
    end
    local easingComboHelpLabel = vgui.Create("DLabel", easingSettingsForm)
    easingComboHelpLabel:SetText("To use a custom easing graph, set the Easing type to \"Custom\".")
    easingComboHelpLabel:SetTextColor(Color(0, 0, 128))
    easingComboHelpLabel:SetWrap(true)
    easingSettingsForm:AddItem(easingComboHelpLabel)
    local custom_easing_button = easingSettingsForm:Button("Edit Custom Easing", "actionrecorder_edit_custom_easing")
    custom_easing_button:SetSize(150, 20)
    custom_easing_button:SetImage("icon16/page_white_edit.png")
    custom_easing_button:SetTooltip("To use an easing type that utilizes the graph you made in the editor, set the easing type to the \"Custom\" option")
    custom_easing_button.DoClick = function()
        vgui.Create("ActionRecorderGraphEditor")
    end
    easingSettingsForm:NumSlider("Easing Amplitude", "actionrecorder_easing_amplitude", 0, 10, 2)
    easingSettingsForm:NumSlider("Easing Frequency", "actionrecorder_easing_frequency", 0, 10, 2)
    easingSettingsForm:CheckBox("Invert Easing", "actionrecorder_easing_invert")
    easingSettingsForm:NumSlider("Easing Offset", "actionrecorder_easing_offset", -1, 1, 2)

    local sectionDivider2 = vgui.Create("DPanel", panel)
    sectionDivider2:SetTall(2)
    sectionDivider2:SetBackgroundColor(Color(50, 50, 50, 200))
    sectionDivider2:Dock(TOP)
    sectionDivider2:DockMargin(0, 5, 0, 5)
    panel:AddItem(sectionDivider2)

    
    local clientSettingsForm = vgui.Create("DForm", panel)
    clientSettingsForm:SetName("Client Settings")
    clientSettingsForm:Dock(TOP)
    clientSettingsForm:DockMargin(0, 5, 0, 5)
    panel:AddItem(clientSettingsForm)
    colorHeader(clientSettingsForm, color_blue)
    clientSettingsForm:CheckBox("Enable HUD", "ar_enable_hud")
    clientSettingsForm:CheckBox("Enable Custom Placement Sounds", "ar_enable_sounds")
    clientSettingsForm:CheckBox("Enable Film Grain Effect", "ar_enable_filmgrain")
end




function TOOL:GetSetConVars(ply)
    local globalMode = GetConVar("actionrecorder_globalmode"):GetBool()
    local cvars = {
        "actionrecorder_playbackspeed",
        "actionrecorder_loop",
        "actionrecorder_playbacktype",
		"actionrecorder_freezeonend",
		"ar_physicsless_teleport",
        "actionrecorder_model",
        "actionrecorder_boxid",
        "actionrecorder_key",
        "actionrecorder_soundpath",
        "actionrecorder_startsound",
        "actionrecorder_stopsound",
        "actionrecorder_hudmaterial",
        "actionrecorder_easing",
        "actionrecorder_easing_amplitude",
        "actionrecorder_easing_frequency",
        "actionrecorder_easing_invert",
        "actionrecorder_easing_offset",
		"actionrecorder_labelcolor_r",
		"actionrecorder_labelcolor_g",
		"actionrecorder_labelcolor_b",
		"actionrecorder_labelcolor_a",
		"actionrecorder_labelcolor_rainbow",
		"actionrecorder_reverseplayback",
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



if CLIENT then

    
    net.Receive("ActionRecorder_PlayStartSound", function()
        if not GetConVar("ar_enable_sounds"):GetBool() then return end
        surface.PlaySound("action_recorder/start_recording.wav")
    end)

    net.Receive("ActionRecorder_PlayStopSound", function()
        if not GetConVar("ar_enable_sounds"):GetBool() then return end
        surface.PlaySound("action_recorder/stop_recording.wav")
    end)

    net.Receive("ActionRecorderNotify", function()
        local msg = net.ReadString()
        local typ = net.ReadInt(3)
        notification.AddLegacy(msg, typ, 5)
    end)

    local loopActive = false
    local LOOP_FILE = "action_recorder/recording_loop.wav"
    local LOOP_DURATION = 1.2

    local function PlayLoopSound()
        if not loopActive then return end
        surface.PlaySound(LOOP_FILE)
        timer.Simple(LOOP_DURATION, PlayLoopSound)
    end

    net.Receive("ActionRecorder_PlayLoopSound", function()
        if not GetConVar("ar_enable_sounds"):GetBool() then return end
        loopActive = true
        PlayLoopSound()
    end)

    net.Receive("ActionRecorder_StopLoopSound", function()
        loopActive = false
    end)

    local flashAlpha = 0
    local flashStartTime = 0
    local flashDuration = 0.2 -- seconds

    net.Receive("ActionRecorder_FlashEffect", function()
        flashAlpha = 255
        flashStartTime = CurTime()
    end)

    hook.Add("HUDPaint", "ActionRecorder_FlashEffect", function()
        if flashAlpha > 0 then
            local elapsed = CurTime() - flashStartTime
            local progress = math.min(elapsed / flashDuration, 1)
            local alpha = 255 * (1 - progress)

            surface.SetDrawColor(255, 255, 255, alpha)
            surface.DrawRect(0, 0, ScrW(), ScrH())

            if progress >= 1 then
                flashAlpha = 0
            end
        end
    end)

    
    local function SendLabelColorToServer(r, g, b, a, rainbow)
        net.Start("ActionRecorder_UpdateLabel")
        net.WriteUInt(r, 8)
        net.WriteUInt(g, 8)
        net.WriteUInt(b, 8)
        net.WriteUInt(a, 8)
        net.WriteBool(rainbow)
        net.SendToServer()
    end

    
    local PANEL = {}

    function PANEL:Init()
        self:SetSize(350, 220)
        self:SetTitle("Select Label Color")
        self:Center()
        self:MakePopup()

        
        self.ColorPreviewLabel = vgui.Create("DLabel", self)
        self.ColorPreviewLabel:SetText("Preview")
        self.ColorPreviewLabel:SetFont("DermaLarge")
        self.ColorPreviewLabel:Dock(TOP)
        self.ColorPreviewLabel:DockMargin(10, 15, 10, 10)
        self.ColorPreviewLabel:SizeToContents()

        
        local r = GetConVar("action_recorder_label_r") and GetConVar("action_recorder_label_r"):GetInt() or 255
        local g = GetConVar("action_recorder_label_g") and GetConVar("action_recorder_label_g"):GetInt() or 255
        local b = GetConVar("action_recorder_label_b") and GetConVar("action_recorder_label_b"):GetInt() or 255
        local a = GetConVar("action_recorder_label_a") and GetConVar("action_recorder_label_a"):GetInt() or 255
        local rainbow = GetConVar("action_recorder_label_rainbow") and GetConVar("action_recorder_label_rainbow"):GetBool() or false

        self.ColorPreviewLabel:SetTextColor(Color(r, g, b, a))

        
        self.ColorMixer = vgui.Create("DColorMixer", self)
        self.ColorMixer:Dock(FILL)
        self.ColorMixer:SetColor(Color(r, g, b, a))

        
        self.RainbowCheckbox = vgui.Create("DCheckBoxLabel", self)
        self.RainbowCheckbox:SetText("Enable Rainbow")
        self.RainbowCheckbox:Dock(TOP)
        self.RainbowCheckbox:DockMargin(10, 5, 10, 10)
        self.RainbowCheckbox:SetValue(rainbow)
        
        
        self.RainbowHue = 0
        self.RainbowActive = rainbow

        
        self.Think = function()
            local previous = self.RainbowActive
            self.RainbowActive = self.RainbowCheckbox:GetChecked()
            if self.RainbowActive then
                self.ColorMixer:SetDisabled(true)
                self.RainbowHue = (self.RainbowHue + 0.01) % 1
                local color = HSVToColor(self.RainbowHue * 360, 1, 1)
                color.a = self.ColorMixer:GetColor().a or 255
                self.ColorPreviewLabel:SetTextColor(color)
                self.ColorMixer:SetColor(color)
            else
                self.ColorMixer:SetDisabled(false)
                if previous then
                    
                    local clr = self.ColorMixer:GetColor() or Color(255, 255, 255, 255)
                    self.ColorPreviewLabel:SetTextColor(clr)
                end
            end
        end

        
        self.ColorMixer.ValueChanged = function(_, clr)
            if self.RainbowCheckbox:GetChecked() then return end
            self.ColorPreviewLabel:SetTextColor(clr)

            RunConsoleCommand("action_recorder_label_r", clr.r)
            RunConsoleCommand("action_recorder_label_g", clr.g)
            RunConsoleCommand("action_recorder_label_b", clr.b)
            RunConsoleCommand("action_recorder_label_a", clr.a)

            SendLabelColorToServer(clr.r, clr.g, clr.b, clr.a, false)
        end

        
        self.RainbowCheckbox.OnChange = function(_, val)
            self.RainbowActive = val
            RunConsoleCommand("action_recorder_label_rainbow", val and "1" or "0")

            local clr = self.ColorMixer:GetColor() or Color(255, 255, 255, 255)
            SendLabelColorToServer(clr.r, clr.g, clr.b, clr.a, val)
        end
    end

    
    vgui.Register("MyColorPicker", PANEL, "DFrame")
end
