# Lua 5.1 Syntax Validation

## Critical: WoW Classic Uses Lua 5.1

World of Warcraft Classic Anniversary uses **Lua 5.1**, which has significant syntax limitations compared to newer Lua versions. **ALWAYS verify code is compatible with Lua 5.1** before making changes.

## Syntax Features NOT Available in Lua 5.1

### ❌ Forbidden Syntax

1. **`goto` statement** - Added in Lua 5.2
   ```lua
   -- ❌ WRONG (Lua 5.2+)
   goto continue
   ::continue::
   
   -- ✅ CORRECT (Lua 5.1)
   if condition then
       -- code here
   end
   ```

2. **Bitwise operators** (`&`, `|`, `~`, `<<`, `>>`) - Added in Lua 5.3
   ```lua
   -- ❌ WRONG (Lua 5.3+)
   local result = a & b
   
   -- ✅ CORRECT (Lua 5.1) - use bit library if available
   local result = bit.band(a, b)
   ```

3. **Integer division operator** (`//`) - Added in Lua 5.3
   ```lua
   -- ❌ WRONG (Lua 5.3+)
   local result = a // b
   
   -- ✅ CORRECT (Lua 5.1)
   local result = math.floor(a / b)
   ```

4. **`_ENV` variable** - Added in Lua 5.2
   ```lua
   -- ❌ WRONG (Lua 5.2+)
   _ENV.var = value
   
   -- ✅ CORRECT (Lua 5.1)
   _G.var = value
   ```

5. **`\z` escape sequence** - Added in Lua 5.2
   ```lua
   -- ❌ WRONG (Lua 5.2+)
   local str = "line 1\z
   line 2"
   
   -- ✅ CORRECT (Lua 5.1)
   local str = "line 1\nline 2"
   ```

## ✅ Valid Lua 5.1 Syntax

### Control Flow
- `if/then/elseif/else/end`
- `while/do/end`
- `repeat/until`
- `for/do/end` (numeric and generic)
- `break` (inside loops only)
- `return`

### Functions
- Function definitions: `function name() end` or `local name = function() end`
- Variable arguments: `function name(...) end`
- Tail calls are optimized

### Tables
- Table constructors: `{}`, `{key = value}`, `{[key] = value}`
- Table access: `t[key]` or `t.key`
- `#` operator for array length (but beware: stops at first nil)

### Operators
- Arithmetic: `+`, `-`, `*`, `/`, `%`, `^`
- Comparison: `==`, `~=`, `<`, `>`, `<=`, `>=`
- Logical: `and`, `or`, `not`
- Concatenation: `..`
- Length: `#`

### Metatables
- `getmetatable()`, `setmetatable()`
- `__index`, `__newindex`, `__call`, `__tostring`, etc.

## Common Patterns for Lua 5.1 Compatibility

### Skipping Iterations (instead of `goto continue`)
```lua
-- ✅ CORRECT: Use nested if statements
for i, item in ipairs(items) do
    if item and item.valid then
        -- process item
    end
end

-- ✅ CORRECT: Use a function
local function processItem(item)
    if not item or not item.valid then
        return
    end
    -- process item
end

for i, item in ipairs(items) do
    processItem(item)
end
```

### Early Returns
```lua
-- ✅ CORRECT: Use return for early exit
local function process(data)
    if not data then
        return nil
    end
    -- continue processing
end
```

## Verification Checklist

Before committing Lua code changes, verify:

- [ ] No `goto` statements or labels (`::label::`)
- [ ] No bitwise operators (`&`, `|`, `~`, `<<`, `>>`)
- [ ] No integer division (`//`)
- [ ] No `_ENV` variable usage
- [ ] No `\z` escape sequences
- [ ] All control flow uses valid Lua 5.1 syntax
- [ ] Table operations use Lua 5.1 compatible methods
- [ ] String operations use Lua 5.1 compatible methods

## Testing

When in doubt, test syntax compatibility by:
1. Checking WoW API documentation for Lua version
2. Testing code in-game (WoW Classic will error on invalid syntax)
3. Using a Lua 5.1 interpreter/checker if available

## References

- [Lua 5.1 Manual](https://www.lua.org/manual/5.1/)
- [Lua 5.1 vs 5.2 Differences](https://www.lua.org/manual/5.2/manual.html#8)
- WoW Classic uses Lua 5.1 (confirmed in WoW API documentation)
