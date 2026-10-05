class_name JoinCode
extends RefCounted
## Short, typeable codes for a host's LAN address, for networks that block
## discovery broadcasts (hotel, campus and guest Wi-Fi).
##
## Common private ranges get short codes: 192.168.x.y on the default port is
## 5 characters. Codes use Crockford base32 (no I, L, O or U), are
## case-insensitive, and treat O as 0 and I or L as 1 when typed.

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


static func encode(ip: String, port: int, default_port: int) -> String:
	var octets := ip.split(".")
	if octets.size() != 4:
		return ""
	var b: Array[int] = []
	for o in octets:
		b.append(o.to_int())
	var bytes := PackedByteArray()
	var custom_port := port != default_port
	# Header nibble: 0 = 192.168.x.y, 1 = 10.x.y.z, 2 = 172.16-31.x.y, 3 = any.
	if b[0] == 192 and b[1] == 168:
		bytes = PackedByteArray([0 | (int(custom_port) << 2), b[2], b[3]])
	elif b[0] == 10:
		bytes = PackedByteArray([1 | (int(custom_port) << 2), b[1], b[2], b[3]])
	elif b[0] == 172 and b[1] >= 16 and b[1] <= 31:
		bytes = PackedByteArray([2 | (int(custom_port) << 2) | ((b[1] - 16) << 3), b[2], b[3]])
	else:
		bytes = PackedByteArray([3 | (int(custom_port) << 2), b[0], b[1], b[2], b[3]])
	if custom_port:
		bytes.append((port >> 8) & 0xFF)
		bytes.append(port & 0xFF)
	return _to_base32(bytes)


## Returns {"ip": String, "port": int}, or an empty dictionary if invalid.
static func decode(code: String, default_port: int) -> Dictionary:
	var bytes := _from_base32(normalize(code))
	if bytes.is_empty():
		return {}
	var header := bytes[0]
	var kind := header & 0x3
	var custom_port := (header >> 2) & 0x1 == 1
	var ip := ""
	var used := 0
	match kind:
		0:
			if bytes.size() < 3:
				return {}
			ip = "192.168.%d.%d" % [bytes[1], bytes[2]]
			used = 3
		1:
			if bytes.size() < 4:
				return {}
			ip = "10.%d.%d.%d" % [bytes[1], bytes[2], bytes[3]]
			used = 4
		2:
			if bytes.size() < 3:
				return {}
			ip = "172.%d.%d.%d" % [16 + ((header >> 3) & 0xF), bytes[1], bytes[2]]
			used = 3
		3:
			if bytes.size() < 5:
				return {}
			ip = "%d.%d.%d.%d" % [bytes[1], bytes[2], bytes[3], bytes[4]]
			used = 5
	var port := default_port
	if custom_port:
		if bytes.size() < used + 2:
			return {}
		port = (bytes[used] << 8) | bytes[used + 1]
	return {"ip": ip, "port": port}


static func normalize(code: String) -> String:
	var out := ""
	for ch in code.to_upper():
		match ch:
			"O": out += "0"
			"I", "L": out += "1"
			"-", " ": pass
			_:
				if ALPHABET.contains(ch):
					out += ch
	return out


## Formats a code in groups of four for display.
static func pretty(code: String) -> String:
	var out := ""
	for i in code.length():
		if i > 0 and i % 4 == 0:
			out += "-"
		out += code[i]
	return out


static func _to_base32(bytes: PackedByteArray) -> String:
	var out := ""
	var buffer := 0
	var bits := 0
	for byte in bytes:
		buffer = (buffer << 8) | byte
		bits += 8
		while bits >= 5:
			bits -= 5
			out += ALPHABET[(buffer >> bits) & 31]
	if bits > 0:
		out += ALPHABET[(buffer << (5 - bits)) & 31]
	return out


static func _from_base32(code: String) -> PackedByteArray:
	var out := PackedByteArray()
	var buffer := 0
	var bits := 0
	for ch in code:
		var v := ALPHABET.find(ch)
		if v < 0:
			return PackedByteArray()
		buffer = ((buffer << 5) | v) & 0xFFFF
		bits += 5
		if bits >= 8:
			bits -= 8
			out.append((buffer >> bits) & 0xFF)
	return out
