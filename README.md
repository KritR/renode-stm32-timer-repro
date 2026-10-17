# renode-stm32-timer-repro

A minimal reproduction of [Renode](https://renode.io)'s `STM32_Timer` losing
compare events under embassy-stm32's 16-bit time driver.

An STM32G474 [embassy](https://embassy.dev) program toggles PA5 every 100 ms
while a second task loops on `Timer::after_micros(10)`. It uses embassy's
time driver on TIM15 (`time-driver-tim15`) at a 32768 Hz tick
(`tick-hz-32_768`). On Renode 1.17.0's `STM32_Timer`, the toggling stops
when TIM15 first reaches CCR1's half-way compare at 0x8000, one second in,
and nothing runs again until about two seconds later.

```
$ ./run.sh
11 toggles at ms: [0, 99, 199, 299, 399, 499, 599, 699, 799, 899, 2998]
```

Expected: 31 toggles, one every 100 ms. A plain 100 ms blinky without the
polling task does not reproduce it. Neither does writing embassy's register
sequence from the monitor with the CPU halted: it needs a running core.

## Running it

```
rustup target add thumbv7em-none-eabi
./run.sh                             # on Renode's STM32_Timer
./run.sh --patched STM32_Timer.cs    # on a candidate fix
```

`renode` must be on `PATH`, or set `RENODE`. `renode/repro.resc` runs on its
own once the firmware is built: `renode --console --disable-gui renode/repro.resc`.
A prebuilt ELF is attached to this repository's releases.

| Path | What |
|---|---|
| `src/main.rs` | the firmware: a blinky plus a task polling every 10 µs |
| `renode/g474-tim15.repl` | just enough STM32G474: Cortex-M4F, flash, SRAM, an RCC that raises its ready flags, GPIOA with an LED on PA5, and TIM15 as `STM32_Timer` |
| `renode/repro.resc` | load, run 3 s, print when the LED changed |
| `renode/count.py` | the monitor command that records the LED's changes |

## Cause

`CaptureCompareChannel.UpdateTimer()` runs on every DIER, CCER, CR1 and
CCRx write. It re-arms a channel that is already counting towards its match
with `Timer.Value = parent.Value`. That restarts the channel's prescaler
phase, so the channel runs up to a tick behind the counter. Once the counter
reads CCRx, the next write disarms the channel (`parent.Value < Timer.Limit`
no longer holds) although its match is due within that tick. embassy rewrites
DIER on every alarm, so with an alarm due each tick, CCR1's half-way match
and the alarm on CCR2 are both lost at 0x8000. Instrumented:

```
timer15: cc2 disarmed before its match: channel at 0x7FFF, counter at 0x8000, CCR 0x8000
```

## Fix

[`KritR/renode-infrastructure@c90f57d`](https://github.com/KritR/renode-infrastructure/commit/c90f57d780a731bd98b0e82ffe9100bb58b384db)
leaves an armed channel's count alone. It disarms the channel only when its
interrupt or output is turned off, or when CCRx is moved below where it has
counted. The update event still resyncs every channel to the counter.

That commit builds on
[renode-infrastructure#235](https://github.com/renode/renode-infrastructure/pull/235),
which fixes compares at CCRx == 0 and CCRx >= ARR
([renode#1007](https://github.com/renode/renode/issues/1007)). #235 alone
does not fix this reproduction. This change alone fixes it, but longer runs
then hit the CCRx == 0 case: an alarm whose low 16 bits are 0. Together they
pass this reproduction and a suite of 28 embassy firmware tests on STM32G431,
STM32G474 and STM32C092 platforms, with every timer on the patched model.

```
$ ./run.sh --patched ../renode-infrastructure/src/Emulator/Peripherals/Peripherals/Timers/STM32_Timer.cs
31 toggles at ms: [0, 99, 199, ..., 2898, 2998]
```
