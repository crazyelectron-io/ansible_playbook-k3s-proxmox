# file: conf/automation/ruby/sunrise_sunset.rb
# synopsis:


rule "HandleSunrise" do
  description "Update the next sunrise time & turn off the lights when the sun is up day phase changes"
  channel 'astro:sun:home:rise#event', triggered: 'END'
  run do |event|
    logger.info "Astro sunrise end, update next sunrise time and turn off the lights"
    Sunrise_Next << OWM_Tomorrow_Sunrise
    Switch_downstairs&.off
    Switch_outdoor&.off
    DayMode << "DAY"
  end
end


rule "HandleSunset" do
  description "Switch lights on at sunset && and update next sunset time"
  channel 'astro:sun:home:set#event', triggered: 'END'
  run do |event|
    logger.info "Astro sunset end, update next sunset time and turn on the lights"
    Sunset_Next << OWM_Tomorrow_Sunset
    Scene_downstairs << 'Avond beneden'
    Scene_outdoor << 'Avond buiten'
    DayMode << "EVENING"
  end
end

