function dump_table(tbl, indent)
    indent = indent or 0
    local formatting = string.rep("  ", indent)

    for key, value in pairs(tbl) do
        local keyStr = tostring(key)
        if type(value) == "table" then
            print(formatting .. keyStr .. " = {")
            dump_table(value, indent + 1)
            print(formatting .. "}")
        else
            print(formatting .. keyStr .. " = " .. tostring(value))
        end
    end
end

return {
	dump_table = dump_table,
}
