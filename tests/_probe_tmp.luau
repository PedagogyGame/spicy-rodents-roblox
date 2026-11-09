local Data = require("../src/shared/Data")
local d = Data.default()
local lots = d:lots()
print(#lots)
local kinds = {}
for _, l in lots do kinds[l.type] = (kinds[l.type] or 0) + 1 end
local lt = d:lotType("house")
for k, v in lt do print("house", k, typeof(v) == "table" and "tbl" or v) end
local l = lots[5]
for k, v in l do print("lot", k, typeof(v) == "table" and "tbl" or v) end
for k,v in l.params or {} do print("param",k,v) end
local roads = d:roads()
local kc = {}
for _, r in roads do kc[r.kind] = (kc[r.kind] or 0) + 1 end
for k,v in kc do print("road", k, v) end
for k, v in roads[2] do print("rd", k, typeof(v)=="table" and "tbl" or v) end
