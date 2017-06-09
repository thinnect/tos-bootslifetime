/**
 * Boot and lifetime info storage in EEPROM.
 *
 * This solution is reserved for quick infrequent storage events - it is known
 * that the device will reboot. It will not tolerate frequent writes.
 * Makes use of the DeviceParams NvParameter storage module and area.
 *
 * @author Raido Pahtma
 * @license MIT
 **/
#include "BootsLifetime.h"
configuration BootsLifetimeNvStorageC {
	provides {
		interface GetStruct<lifetime_data_t> as GetLifetimeData;
		interface SetStruct<lifetime_data_t> as SetLifetimeData;
	}
}
implementation {

	components new BootsLifetimeNvStorageP();
	GetLifetimeData = BootsLifetimeNvStorageP.GetLifetimeData;
	SetLifetimeData = BootsLifetimeNvStorageP.SetLifetimeData;

	components new NvParameterC(sizeof(lifetime_data_t));
	BootsLifetimeNvStorageP.StoredLifetimeData -> NvParameterC.NvParameter;

}
