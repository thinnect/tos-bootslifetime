/**
 * Boot and lifetime counter wiring.
 *
 * Boot event wiring is left to the application to trigger from the appropriate
 * boot step. The component is however not intended to be wired into the boot
 * chain for most cases, because it will delay the StableBoot event for 60
 * seconds (default configuration).
 *
 * @author Raido Pahtma
 * @license MIT
 **/
#include "BootsLifetime.h"
configuration BootsLifetimeC {
	provides {
		interface Boot as StableBoot;
		interface Get<uint32_t> as BootNumber;
		interface Get<uint32_t> as Lifetime;
		interface Get<uint32_t> as Uptime;
	}
	uses {
		interface Boot; // Must be wired to the correct boot event
		interface Halt; // May be wired to handle halts
		interface GetStruct<lifetime_data_t> as GetLifetimeData;
		interface SetStruct<lifetime_data_t> as SetLifetimeData;
	}
}
implementation {

	components new BootsLifetimeP(2);
	StableBoot = BootsLifetimeP.StableBoot;
	BootNumber = BootsLifetimeP.BootNumber;
	Lifetime = BootsLifetimeP.Lifetime;
	Uptime = BootsLifetimeP.Uptime;

	BootsLifetimeP.Boot = Boot;
	BootsLifetimeP.Halt = Halt;
	BootsLifetimeP.GetLifetimeData = GetLifetimeData;
	BootsLifetimeP.SetLifetimeData = SetLifetimeData;

	components new BlockStorageC(VOLUME_BOOTSLIFETIME1) as Vol1;
	BootsLifetimeP.BlockRead[0] -> Vol1;
	BootsLifetimeP.BlockWrite[0] -> Vol1;

	components new BlockStorageC(VOLUME_BOOTSLIFETIME2) as Vol2;
	BootsLifetimeP.BlockRead[1] -> Vol2;
	BootsLifetimeP.BlockWrite[1] -> Vol2;

	components CrcC;
	BootsLifetimeP.Crc -> CrcC;

	components new TimerMilliC();
	BootsLifetimeP.Timer -> TimerMilliC;

	components LocalTimeSecondC;
	BootsLifetimeP.LocalTimeSecond -> LocalTimeSecondC;

	components LedsC;
	BootsLifetimeP.Leds -> LedsC;

}
