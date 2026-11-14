test("EventBus delivers payload and honors UnsubscribeOwner", function()
    local bus = Pockets.Services.EventBus
    local owner, got = {}, {}
    bus:Subscribe("SIM_TEST", function(p) got[#got + 1] = p end, owner)
    bus:Publish("SIM_TEST", "a")
    assertEquals(1, #got)
    assertEquals("a", got[1])
    bus:UnsubscribeOwner(owner)
    bus:Publish("SIM_TEST", "b")
    assertEquals(1, #got)
end)
