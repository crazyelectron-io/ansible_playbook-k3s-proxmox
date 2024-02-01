# file: conf/automation/ruby/hue_switch.rb
# synopsis: Hue Dimmer/Tap Switch Buttons handling rule

# frozen_string_literal: true

module Hue
  ON_PRESSED = "1000"
  ON_HOLD = "1001"
  ON_SHORT_RELEASED = "1002"
  ON_LONG_RELEASED = "1003"
  BR_PRESSED = "2000"
  BR_HOLD = "2001"
  BR_SHORT_RELEASED = "2002"
  BR_LONG_RELEASED = "2003"
  DIM_PRESSED = "3000"
  DIM_HOLD = "3001"
  DIM_SHORT_RELEASED = "3002"
  DIM_LONG_RELEASED = "3003"
  HUE_PRESSED = "4000"
  HUE_HOLD = "4001"
  HUE_SHORT_RELEASED = "4002"
  HUE_LONG_RELEASED = "4003"
  TAP_LEFT_UP = "16.0"
  TAP_LEFT_DOWN = "17.0"
  TAP_RIGHT_UP = "34.0"
  TAP_RIGHT_DOWN = "18.0"
  TAP_UP = "100.0"    # =keys pressed, 101.0=keys released
  TAP_DOWN = "98.0"   # =keys pressed, 99.0=keys released
  MOTION_ON = "ON"
  MOTION_OFF = "OFF"
end


module Scene
  NAMES = %w[OFF EVENING READ WORK BRIGHT MOVIE COSY].freeze
  NAMES.each { |scene| const_set(scene, scene) }

  # Mapping of Hue switches/dimmers and keys to lighting scenes
  # Primary key is the button pressed
  BUTTON_TO_SCENE = {
    'hallway' => {
      Hue::ON_PRESSED => {zone: nil},
      Hue::ON_HOLD => {zone: nil, scene: nil, off_delay: 0},
      Hue::ON_SHORT_RELEASED => {zone: nil, scene: nil, off_delay: 0},
      Hue::ON_LONG_RELEASED => {zone: 'hallCeiling', scene: 'Hal plafond avond', off_delay: 0},
      Hue::BR_HOLD => {zone: nil, scene: nil, off_delay: 0},
      Hue::DIM_HOLD => {zone: nil, scene: nil, off_delay: 0},
      Hue::HUE_PRESSED => {zone: nil, scene: nil, off_delay: 0},
      Hue::HUE_HOLD => {zone: nil, scene: nil, off_delay: 0},
      Hue::HUE_SHORT_RELEASED => {zone: 'hallCeiling', scene: nil, off_delay: 0},
      Hue::HUE_LONG_RELEASED => {zone: 'hallCeiling', scene: 'Nacht hal plafond', off_delay: 1.minutes}
    },
    'office' => {
      Hue::ON_PRESSED => {zone: nil},
      Hue::ON_HOLD => {zone: nil},
      Hue::ON_SHORT_RELEASED => {zone: nil},
      Hue::ON_LONG_RELEASED => {zone: 'office', scene: 'Lezen', off_delay: 0},
      Hue::BR_HOLD => {zone: nil},
      Hue::DIM_HOLD => {zone: nil},
      Hue::HUE_PRESSED => {zone: nil},
      Hue::HUE_HOLD => {zone: nil},
      Hue::HUE_SHORT_RELEASED => {zone: nil},
      Hue::HUE_LONG_RELEASED => {zone: nil}
    },
    'bedroom' => {
      Hue::ON_PRESSED => {zone: 'bedroom', scene: 'Ontspannen', off_delay: 0},
      Hue::ON_HOLD => {zone: nil},
      Hue::ON_SHORT_RELEASED => {zone: nil},
      Hue::ON_LONG_RELEASED => {zone: nil},
      Hue::BR_HOLD => {zone: nil},
      Hue::DIM_HOLD => {zone: nil},
      Hue::HUE_PRESSED => {zone: 'bedroom', scene: nil},
      Hue::HUE_HOLD => {zone: nil},
      Hue::HUE_SHORT_RELEASED => {zone: nil},
      Hue::HUE_LONG_RELEASED => {zone: nil}
    },
    'stairs' => {
      Hue::ON_PRESSED => {zone: 'corridor', scene: 'Ontspannen', off_delay: 0},
      Hue::ON_HOLD => {zone: nil},
      Hue::ON_SHORT_RELEASED => {zone: nil},
      Hue::ON_LONG_RELEASED => {zone: nil},
      Hue::BR_PRESSED => {zone: 'corridor', scene: 'Lezen'},
      Hue::DIM_HOLD => {zone: nil},
      Hue::HUE_PRESSED => {zone: 'corridor', scene: 'Nachtlampje'},
      Hue::HUE_HOLD => {zone: nil},
      Hue::HUE_SHORT_RELEASED => {zone: nil},
      Hue::HUE_LONG_RELEASED => {zone: nil}
    }
  }.freeze
end


rule "HueDimmerKey" do
  channel [
    'hue:device:br1:dim_hallway:button-last-event',
    'hue:device:br2:dim_office:button-last-event',
    'hue:device:br2:dim_fitness:button-last-event',
    'hue:device:br2:diml_bedroom:button-last-event',
    'hue:device:br2:dimr_bedroom:button-last-event',
    'hue:device:br2:dim_menno:button-last-event',
    'hue:device:br1:dim_corridor:button-last-event',
    'hue:device:br2:dimu_corridor:button-last-event',
    'hue:device:br1:dimf_hall:button-last-event',
    'hue:device:br1:dim_stairs:button-last-event'
  ]
  run do |event|
    # Extract the relevant data from the event
    switch_name = event.channel.to_s.split(":")[3].split("_")[1]
    key_pressed = event.event.to_s
    logger.info "DBG01: Switch [#{switch_name}], Key pressed [#{key_pressed}]"

    next unless Scene::BUTTON_TO_SCENE[switch_name]   # No entry for this switch/dimmer?
    zone_name = Scene::BUTTON_TO_SCENE[switch_name][key_pressed][:zone] || nil
    scene_name = Scene::BUTTON_TO_SCENE[switch_name][key_pressed][:scene] || nil
    scene_off_delay = Scene::BUTTON_TO_SCENE[switch_name][key_pressed][:off_delay] || 0
    processing = scene_name.nil? && zone_name.nil? ? "key ignored" : "key will be processed" # For debug logging only
    logger.info "DBG02: Zone [#{zone_name || 'nil'}], Scene [#{scene_name || 'nil'}], off_delay [#{scene_off_delay}]; #{processing}"

    unless zone_name.nil?
      scene_item = "Scene_" + zone_name
      logger.info "Event [#{event}], switch [#{switch_name}], key [#{key_pressed}], zone [#{zone_name}], scene [#{scene_name}], item [#{scene_item}], item.state [#{items[scene_item].state}]"
      if items[scene_item].state.nil? or items[scene_item].state == "UNDEF"
        logger.info "DBG03: Current scene state is nil or [UNDEF]; Set scene item #{scene_item} to #{scene_name}"
        items[scene_item].command(scene_name) unless scene_name.nil?
      end
      switch_item = "Switch_"+zone_name
      if scene_off_delay > 0
        logger.info "DBG04: #{switch_item} off after #{scene_off_delay}"
        after (scene_off_delay) { items[switch_item].ensure.off }
      else
          logger.info "DBG05: #{switch_item} off now"
          items[switch_item].ensure.off
      end
      #   unless follow_item.nil?
      #     items[follow_item] << follow_scene
      #     after (scene_off_delay) {items[follow_item].off }
      #   end
    end
  end
end


rule "MotionToiletDetected" do
  description "Change light in toilet based on motion"
  changed MotionDetected_toilet, to: ON
  run { Switch_toilet.on for: 5.minute  }
end
