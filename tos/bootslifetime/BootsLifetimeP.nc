/**
 * Boot and lifetime counter.
 *
 * Writes stats to several volumes, erases volume before first write to that
 * volume, switches to next volume if the previous one becomes full or on boot.
 *
 * @author Raido Pahtma
 * @license MIT
 **/
#include "sec_tmilli.h"
#include "BootsLifetime.h"
generic module BootsLifetimeP(uint8_t volumes) {
	provides {
		interface Boot as StableBoot;
		interface Get<uint32_t> as BootNumber;
		interface Get<uint32_t> as Lifetime;
		interface Get<uint32_t> as Uptime;
	}
	uses {
		interface Boot @exactlyonce();
		interface Halt;

		interface Timer<TMilli>;
		interface LocalTime<TSecond> as LocalTimeSecond;

		interface GetStruct<lifetime_data_t> as GetLifetimeData; // Support additional storage for lifetime data
		interface SetStruct<lifetime_data_t> as SetLifetimeData; // Support additional storage for lifetime data

		interface BlockRead[uint8_t volume];
		interface BlockWrite[uint8_t volume];
		interface Crc;

		interface Leds;
	}
}
implementation {

	#define __MODUUL__ "BLT"
	#define __LOG_LEVEL__ ( LOG_LEVEL_BootsLifetimeP & BASE_LOG_LEVEL )
	#include "log.h"

	typedef struct boot_lifetime {
		uint32_t boot;
		uint32_t lifetime;
		uint32_t uptime;
		uint16_t crc;
	} boot_lifetime_t;

	enum BootsLifetimeStates {
		BLT_ST_OFF,
		BLT_ST_READ,
		BLT_ST_IDLE,
		BLT_ST_WRITE,
		BLT_ST_ERASE,
		BLT_ST_SYNC
	};

	typedef struct blf_state {
		uint8_t state : 3;
		bool booted : 1;
		uint8_t vol : 2;
		uint8_t master_vol: 2;
		uint8_t master_offset;
		uint8_t offset;
	} blf_state_t;

	blf_state_t m = { BLT_ST_OFF, FALSE, 0, 0, 0, 0 };

	boot_lifetime_t m_blf = { 0, 0, 0, 0 };
	boot_lifetime_t m_buf;

	bool blt_good(boot_lifetime_t* blt) {
		uint16_t crc = call Crc.crc16(blt, sizeof(boot_lifetime_t)-sizeof(uint16_t));
		return crc == blt->crc;
	}

	void blt_protect(boot_lifetime_t* blt) {
		blt->crc = call Crc.crc16(blt, sizeof(boot_lifetime_t)-sizeof(uint16_t));
	}

	command uint32_t BootNumber.get() {
		return m_blf.boot;
	}

	command uint32_t Lifetime.get() {
		return m_blf.lifetime + call Uptime.get();
	}

	command uint32_t Uptime.get() {
		return call LocalTimeSecond.get();
	}

	event void Boot.booted() {
		lifetime_data_t ld;
		if(call GetLifetimeData.get(&ld) == SUCCESS) {
			m_blf.boot = ld.boots + 1;
			m_blf.lifetime = ld.lifetime;
			m_blf.uptime = call Uptime.get();
			debug1("init %"PRIu32" %"PRIu32"+%"PRIu32, m_blf.boot, m_blf.lifetime, m_blf.uptime);
		}
		m.state = BLT_ST_READ;
		call Timer.startOneShot(0);
	}

	event error_t Halt.halt(uint32_t grace) {
		if(m.state > BLT_ST_OFF) {
			lifetime_data_t ld;
			ld.lifetime = m_blf.lifetime + call Uptime.get();
			ld.boots = m_blf.boot;
			debug1("halt %"PRIu32" %"PRIu32"+%"PRIu32, m_blf.boot, m_blf.lifetime, m_blf.uptime);
			call SetLifetimeData.set(&ld);
		}
		return SUCCESS;
	}

	event void Timer.fired() {
		error_t err = FAIL;
		switch(m.state) {
			case BLT_ST_IDLE:
				if(blt_good(&m_blf)) {
					m_blf.uptime = call Uptime.get();
					blt_protect(&m_blf);
					m.state = BLT_ST_WRITE;
				}
				else { // Memory corruption .. this is really bad ... try to recover latest info from flash
					errb1("mem", &m_blf, sizeof(m_blf));
					call Leds.set(1);
					call Leds.set(3);
					call Leds.set(7);
					while(1); // Stop all execution, force a reboot
				}
				call Timer.startOneShot(0);
				return; // Proceed to next state

			case BLT_ST_READ:
				err = call BlockRead.read[m.vol]((storage_addr_t)m.offset*sizeof(boot_lifetime_t), &m_buf, sizeof(boot_lifetime_t));
			break;

			case BLT_ST_ERASE:
				err = call BlockWrite.erase[m.vol]();
			break;

			case BLT_ST_WRITE:
				err = call BlockWrite.write[m.vol]((storage_addr_t)m.offset*sizeof(boot_lifetime_t), &m_blf, sizeof(boot_lifetime_t));
			break;

			case BLT_ST_SYNC:
				err = call BlockWrite.sync[m.vol]();
			break;

			default:
				err1("dflt");
			break;
		}

		if(err != SUCCESS) {
			err1("blt[%u:%u] %u = %u", m.vol, m.offset, m.state, err);
			call Timer.startOneShot(BOOTSLIFETIME_RETRY_PERIOD_MS);
		}
	}

	event void BlockRead.readDone[uint8_t volume](storage_addr_t addr, void* buf, storage_len_t len, error_t err) {
		logger(err == SUCCESS ? LOG_DEBUG1: LOG_WARN1, "rD[%u](%"PRIu32",_,%u,%u)", volume, addr, len, err);
		if((err == SUCCESS)&&(blt_good(&m_buf))) {
			if(m_buf.lifetime + m_buf.uptime > m_blf.lifetime) {
				m_blf.boot = m_buf.boot + 1;
				m_blf.lifetime = m_buf.lifetime + m_buf.uptime; // Add up lifetime and uptime from previous boot
				m_blf.uptime = call Uptime.get();
				blt_protect(&m_blf);

				m.master_offset = m.offset;
				m.master_vol = m.vol;
			}
		}

		m.offset++;
		if((storage_addr_t)m.offset*sizeof(boot_lifetime_t) + sizeof(boot_lifetime_t) > call BlockRead.getSize[m.vol]()) {
			m.vol++;
			m.offset = 0;
		}

		if(m.vol >= volumes) { // Searched through everything
			debug1("boot %"PRIu32" %"PRIu32"+%"PRIu32, m_blf.boot, m_blf.lifetime, m_blf.uptime);

			m.vol = m.master_vol + 1;
			if(m.vol >= volumes) {
				m.vol = 0;
			}
			m.offset = 0;
			m.state = BLT_ST_ERASE;
			call Timer.startOneShot(SEC_TMILLI(BOOTSLIFETIME_STABILIZATION_PERIOD_S));
		}
		else {
			call Timer.startOneShot(BOOTSLIFETIME_ACTION_DELAY_MS);
		}
	}

	event void BlockWrite.writeDone[uint8_t volume](storage_addr_t addr, void* buf, storage_len_t len, error_t err) {
		logger(err == SUCCESS ? LOG_DEBUG1: LOG_WARN1, "wD[%u](%"PRIu32",_,%u,%u)", volume, addr, len, err);
		m.offset++;
		if((storage_addr_t)m.offset*sizeof(boot_lifetime_t) + sizeof(boot_lifetime_t) > call BlockRead.getSize[m.vol]()) {
			m.vol++;
			m.offset = 0;
			if(m.vol >= volumes) {
				m.vol = 0;
			}
		}

		if(m.booted == FALSE) {
			m.booted = TRUE;
			signal StableBoot.booted();
		}

		if(err == SUCCESS) { // Sync only if write was successful
			m.state = BLT_ST_SYNC;
			call Timer.startOneShot(BOOTSLIFETIME_ACTION_DELAY_MS);
		}
		else {
			m.state = BLT_ST_IDLE;
			call Timer.startOneShot(SEC_TMILLI(BOOTSLIFETIME_STORAGE_PERIOD_S));
		}
	}

	event void BlockWrite.eraseDone[uint8_t volume](error_t err) {
		logger(err == SUCCESS ? LOG_DEBUG1: LOG_WARN1, "eD[%u](%u)", volume, err);
		if(err == SUCCESS) {
			m.state = BLT_ST_IDLE;
			call Timer.startOneShot(BOOTSLIFETIME_ACTION_DELAY_MS);
		}
		else {
			call Timer.startOneShot(BOOTSLIFETIME_RETRY_PERIOD_MS);
		}
	}

	event void BlockWrite.syncDone[uint8_t volume](error_t err) {
		logger(err == SUCCESS ? LOG_DEBUG1: LOG_WARN1, "sD[%u](%u)", volume, err);
		m.state = BLT_ST_IDLE;
		call Timer.startOneShot(SEC_TMILLI(BOOTSLIFETIME_STORAGE_PERIOD_S));
	}

	event void BlockRead.computeCrcDone[uint8_t volume](storage_addr_t addr, storage_len_t len, uint16_t crc, error_t err) { }

	default command error_t BlockRead.read[uint8_t volume](storage_addr_t addr, void* buf, storage_len_t len) { return ELAST; }
	default command storage_len_t BlockRead.getSize[uint8_t volume]() { return 0; }

	default command error_t BlockWrite.write[uint8_t volume](storage_addr_t addr, void* buf, storage_len_t len) { return ELAST; }
	default command error_t BlockWrite.erase[uint8_t volume]() { return ELAST; }
	default command error_t BlockWrite.sync[uint8_t volume]() { return ELAST; }

	default command error_t GetLifetimeData.get(lifetime_data_t* ld) { return ELAST; }
	default command error_t SetLifetimeData.set(lifetime_data_t* ld) { return ELAST; }

}
