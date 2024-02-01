# file: conf/automation/ruby/set_daymode.rb
# synopsis: Set the day mode based on time, cloudiness and sunset/sunrise.

module Phases
  # Astro day phases translation to day mode
  # SUN_RISE, ASTRO_DAWN, NAUTIC_DAWN, CIVIL_DAWN, CIVIL_DUSK, NAUTIC_DUSK, ASTRO_DUSK, SUN_SET, DAYLIGHT, NIGHT
  DAY_PHASES = {
    'DAYLIGHT' => {
      "mode" => "time",
      "mode_time" => 5,
      "before_state" => "MORNING",
      "after_state" => "DAY"
    },
    'SUN_SET' => {
      'mode' => "cloud",
      'cloudy_state' => "EVENING",
      'clear_state' => "DAY"
    },
    'SUN_RISE' => {
      'mode' => "cloud",
      'cloudy_state' => "MORNING",
      'clear_state' => "DAY"
    },
    'ASTRO_DAWN' => {
      'mode' => "time",
      'mode_time' => 5,
      'before_state' => "NIGHT",
      'after_state' => "MORNING"
    },
    'NAUTIC_DAWN' => {
      'mode' => "time",
      'mode_time' => 5,
      'before_state' => "NIGHT",
      'after_state' => "MORNING"
    },
    'CIVIL_DAWN' => {
      'mode' => "time",
      'mode_time' => 5,
      'before_state' => "NIGHT",
      'after_state' => "MORNING"
    },
    'ASTRO_DUSK' => {
      'mode' => "time",
      'mode_time' => 23,
      'before_state' => "EVENING",
      'after_state' => "NIGHT"
    },
    'NAUTIC_DUSK' => {
      'mode' => "time",
      'mode_time' => 23,
      'before_state' => "EVENING",
      'after_state' => "NIGHT"
    },
    'CIVIL_DUSK' => {
      'mode' => "time",
      'mode_time' => 23,
      'before_state' => "EVENING",
      'after_state' => "NIGHT"
    },
    'NIGHT' => {
      'mode' => "astro",
      'mode_time' => 00,
      'before_state' => "NIGHT",
      'after_state' => "NIGHT"
    },
    'NOON' => {
      'mode' => "time",
      'mode_time' => 12,
      'before_state' => "DAY",
      'after_state' => "DAY"
    }
  }.freeze
end


rule "SetDayMode" do
  description "Update current DayMode based on time, weather and sun position"
  changed Astro_DayPhase,OWM_Current_Cloudiness
  run do |event|
    next unless event.state?
    logger.debug "Enter with Event [#{event}], DayMode [#{DayMode.state}], Clouds [#{OWM_Current_Cloudiness.state}], Astro_DayPhase [#{Astro_DayPhase.state}]" unless event.nil?

    key = Phases::DAY_PHASES[Astro_DayPhase.state.to_s]
    mode = key['mode']
    case key['mode']
      when "time"
        newState = ZonedDateTime.now().getHour() < key["mode_time"] ? key["before_state"] : key["after_state"]
        newState = "NIGHT" if %w["NIGHT" "NAUTIC_DAWN" "CIVIL_DAWN" "ASTRO_DAWN"].include?(Astro_DayPhase.to_s) && newState == "EVENING"
      when "cloud"
        newState = OWM_Current_Cloudiness.state == 1 ? key["clear_state"] : key["cloudy_state"]
      when "astro"
        newState = key["before_state"]
    end

    logger.info "Set DayMode to #{newState}, from #{DayMode.state}" unless newState == DayMode.state
    DayMode.ensure << newState
  end
end

# # rise, set, noon, night, morningNight, astroDawn, nauticDawn, civilDawn, astroDusk, nauticDusk, civilDusk, eveningNight, daylight
# rule "UpdateDayMode" do
#   description "Update DayMode based on Astro events"
#   channel "astro:sun:home:rise"
