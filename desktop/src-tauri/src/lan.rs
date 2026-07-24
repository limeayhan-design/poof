use crate::LanPeer;
use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use parking_lot::Mutex;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use tauri::{AppHandle, Emitter};

const SERVICE_TYPE: &str = "_poof._tcp.local.";

/// Runs the mDNS daemon in the background:
///   * advertises this device as `_poof._tcp.local.`
///   * browses for peers and forwards them to the frontend
pub struct LanService {
    daemon: ServiceDaemon,
    stop_flag: Arc<AtomicBool>,
    fullname: Mutex<Option<String>>,
}

impl LanService {
    pub fn start(app: AppHandle) -> Result<Self, mdns_sd::Error> {
        let daemon = ServiceDaemon::new()?;
        let receiver = daemon.browse(SERVICE_TYPE)?;
        let stop = Arc::new(AtomicBool::new(false));
        let stop_thread = stop.clone();

        thread::spawn(move || {
            while !stop_thread.load(Ordering::Relaxed) {
                match receiver.recv_timeout(std::time::Duration::from_millis(500)) {
                    Ok(ServiceEvent::ServiceResolved(info)) => {
                        let props = info.get_properties();
                        let device_id = props
                            .get_property_val_str("deviceId")
                            .unwrap_or("")
                            .to_string();
                        let name = props
                            .get_property_val_str("name")
                            .unwrap_or("Unknown")
                            .to_string();
                        let platform = props
                            .get_property_val_str("platform")
                            .unwrap_or("desktop")
                            .to_string();
                        let host = info
                            .get_addresses()
                            .iter()
                            .next()
                            .map(|a| a.to_string())
                            .unwrap_or_default();
                        let port = info.get_port();

                        if !device_id.is_empty() {
                            let peer = LanPeer {
                                device_id,
                                name,
                                platform,
                                host,
                                port,
                            };
                            let _ = app.emit("lan-peer-found", peer);
                        }
                    }
                    Ok(ServiceEvent::ServiceRemoved(_ty, fullname)) => {
                        let _ = app.emit("lan-peer-lost", fullname);
                    }
                    Ok(_) => {}
                    Err(flume::RecvTimeoutError::Timeout) => continue,
                    Err(_) => break,
                }
            }
        });

        Ok(Self {
            daemon,
            stop_flag: stop,
            fullname: Mutex::new(None),
        })
    }

    /// Register (or re-register) this device on the LAN.
    /// Uses a stable instance name derived from the device id, so re-advertising
    /// with a new name replaces the old TXT record.
    pub fn advertise(&self, device_id: &str, name: &str) -> Result<(), mdns_sd::Error> {
        let short_id: String = device_id.chars().take(12).collect();
        let instance = format!("poof-{}", short_id);
        let hostname_owned = format!("poof-{}.local.", short_id);
        let ip = local_ip_address::local_ip()
            .map(|a| a.to_string())
            .unwrap_or_else(|_| "0.0.0.0".to_string());

        let mut props: HashMap<String, String> = HashMap::new();
        props.insert("deviceId".into(), device_id.into());
        props.insert("name".into(), name.into());
        props.insert("platform".into(), "desktop".into());

        let info = ServiceInfo::new(
            SERVICE_TYPE,
            &instance,
            &hostname_owned,
            ip.as_str(),
            0,
            Some(props),
        )?;

        // If a previous instance was registered, unregister first to avoid ghost entries.
        {
            let mut guard = self.fullname.lock();
            if let Some(prev) = guard.take() {
                let _ = self.daemon.unregister(&prev);
            }
            *guard = Some(format!("{}.{}", instance, SERVICE_TYPE));
        }

        self.daemon.register(info)?;
        Ok(())
    }

    pub fn stop(self) {
        self.stop_flag.store(true, Ordering::Relaxed);
        if let Some(fullname) = self.fullname.lock().take() {
            let _ = self.daemon.unregister(&fullname);
        }
        let _ = self.daemon.shutdown();
    }
}
