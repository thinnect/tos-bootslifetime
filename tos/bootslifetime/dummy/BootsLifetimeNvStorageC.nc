/**
 * Boot and lifetime info storage DUMMY.
 *
 * @author Raido Pahtma
 * @license MIT
 */
#include "BootsLifetime.h"
module BootsLifetimeNvStorageC {
	provides {
		interface GetStruct<lifetime_data_t> as GetLifetimeData;
		interface SetStruct<lifetime_data_t> as SetLifetimeData;
	}
}
implementation {

	#warning "DUMMY BootsLifetimeNvStorageC"

	lifetime_data_t m_ld = { 0, 0 };

	command error_t GetLifetimeData.get(lifetime_data_t* ld) {
		*ld = m_ld;
		return SUCCESS;
	}

	command error_t SetLifetimeData.set(lifetime_data_t* ld) {
		m_ld = *ld;
		return SUCCESS;
	}

}
