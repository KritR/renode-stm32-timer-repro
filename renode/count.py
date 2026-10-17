# Records every change of the LED on PA5, at its virtual time.
from Antmicro.Renode.Core import EmulationManager
_toggles = []
def mc_count_toggles():
    led = monitor.Machine["sysbus.gpioPortA.led"]
    def changed(_led, state):
        _toggles.append(EmulationManager.Instance.CurrentEmulation.MasterTimeSource.ElapsedVirtualTime.TotalMilliseconds)
    led.StateChanged += changed
def mc_toggles():
    print("%d toggles at ms: %s" % (len(_toggles), [int(t) for t in _toggles]))
