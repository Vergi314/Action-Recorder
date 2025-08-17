if SERVER then
    util.AddNetworkString("ActionRecorder_TogglePause_Targeted")

    net.Receive("ActionRecorder_TogglePause_Targeted", function(len, ply)
        if not IsValid(ply) then return end

        local trace = ply:GetEyeTrace()
        if not trace.Hit or not IsValid(trace.Entity) or trace.Entity:GetClass() ~= "action_playback_box" then return end

        local box = trace.Entity
        if box:GetPos():Distance(ply:GetPos()) > 256 then return end -- Optional distance check

        box:TogglePause()
    end)
end
