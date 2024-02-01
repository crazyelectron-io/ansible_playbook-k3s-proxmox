rule "TestItemBuild" do
  description "test building items at runtime"
  on_start at_level: 40
  run {
    items.build do
      switch_item MySwitch, "My Switch"
      switch_item NotAutoupdating, autoupdate: false, channel: "mqtt:topic:1#light"
      group_item MyGroup do
        contact_item ItemInGroup, channel: "binding:thing#channel"
      end
      # passing `thing` to a group item will automatically use it as the base
      # for item channels
      group_item Equipment, tags: Semantics::HVAC, thing: "binding:thing"
        string_item Mode, tags: Semantics::Control, channel: "mode"
      end

      # dimension Temperature inferred
      number_item OutdoorTemp, format: "%.1f %unit%", unit: "°F"

      # unit lx, dimension Illuminance, format "%s %unit%" inferred
      number_item OutdoorBrightness, state: 10_000 | "lx"
    end
  }
end
