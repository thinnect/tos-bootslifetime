/**
 * Boot and lifetime info storage in EEPROM.
 *
 * @author Raido Pahtma
 * @license MIT
 */
#include "BootsLifetime.h"
generic module BootsLifetimeNvStorageP() {
	provides {
		interface GetStruct<lifetime_data_t> as GetLifetimeData;
		interface SetStruct<lifetime_data_t> as SetLifetimeData;
	}
	uses {
		interface NvParameter as StoredLifetimeData;
	}
}
implementation {

	#define __MODUUL__ "blts"
	#define __LOG_LEVEL__ ( LOG_LEVEL_BootsLifetimeNvStorageP & BASE_LOG_LEVEL )
	#include "log.h"

	PROGMEM const char m_parameter_id[] = "bootslifetime";

	lifetime_data_t m_ld = { 0, 0 };

	command error_t GetLifetimeData.get(lifetime_data_t* ld) {
		*ld = m_ld;
		return SUCCESS;
	}

	command error_t SetLifetimeData.set(lifetime_data_t* ld) {
		char id[sizeof(m_parameter_id)];
		strcpy_P(id, m_parameter_id);
		m_ld = *ld;
		return call StoredLifetimeData.store(id, &m_ld, sizeof(lifetime_data_t));
	}

	event bool StoredLifetimeData.matches(const char* identifier) { return 0 == strcmp_P(identifier, m_parameter_id); }

	event error_t StoredLifetimeData.init(void* value, uint8_t length) {
		if(length == sizeof(lifetime_data_t)) {
			m_ld = *((lifetime_data_t*)value);
			return SUCCESS;
		}
		return ESIZE;
	}

}
