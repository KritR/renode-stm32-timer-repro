//! Toggles PA5 every 100 ms on embassy's TIM15 time driver at 32768 Hz,
//! while another task waits 10 us at a time, as a polling loop does, so
//! an alarm is due on every tick. On Renode's STM32_Timer the toggling
//! stops at t = 1 s, when TIM15 first reaches CCR1's 0x8000.
#![no_std]
#![no_main]

use embassy_stm32::gpio::{Level, Output, Speed};
use embassy_time::Timer;

#[embassy_executor::task]
async fn poll() {
    loop {
        Timer::after_micros(10).await;
    }
}

#[embassy_executor::main]
async fn main(spawner: embassy_executor::Spawner) {
    let p = embassy_stm32::init(Default::default());
    spawner.spawn(poll().unwrap());
    let mut pin = Output::new(p.PA5, Level::Low, Speed::Low);
    loop {
        pin.toggle();
        Timer::after_millis(100).await;
    }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
