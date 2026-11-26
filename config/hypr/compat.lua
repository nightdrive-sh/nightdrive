-- What differs between the Hyprland versions Nightdrive runs on (0.56 from the COPR, 0.57 once it is rebuilt there), in
-- one place, so the rest of the config reads the same on both. A shim goes once every user has the newer version.

-- A window's stable_id as a number to compare: windows are numbered in the order they opened. 0.56 gives an integer,
-- 0.57 the same id as a hex string (#15869, as hyprctl's JSON always had it), and as strings "a" < "9" and "10" < "9".
function NIGHTDRIVE_STABLE_ID(w)
    local id = w and w.stable_id
    if type(id) == "string" then return tonumber(id, 16) or 0 end
    return id or 0
end
