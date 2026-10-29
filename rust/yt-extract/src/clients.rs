use clap::ValueEnum;
use serde_json::{Value, json};

pub const API_KEY: &str = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8";

#[derive(Debug, Clone, Copy, PartialEq, ValueEnum)]
pub enum Client {
    #[value(name = "visionos")]
    VisionOs,
    #[value(name = "ios")]
    Ios,
    #[value(name = "android_vr")]
    AndroidVr,
    #[value(name = "tv")]
    TvDowngraded,
}

impl Client {
    pub fn label(self) -> &'static str {
        match self {
            Client::VisionOs => "visionos",
            Client::Ios => "ios",
            Client::AndroidVr => "android_vr",
            Client::TvDowngraded => "tv_downgraded",
        }
    }

    /// x-youtube-client-name sent to InnerTube.
    pub fn client_name_id(self) -> &'static str {
        match self {
            Client::VisionOs => "101",
            Client::Ios => "5",
            Client::AndroidVr => "28",
            Client::TvDowngraded => "7",
        }
    }

    pub fn context(self) -> Value {
        match self {
            Client::VisionOs => json!({
                "client": {
                    "clientName": "VISIONOS",
                    "clientVersion": "1.02",
                    "deviceMake": "Apple",
                    "deviceModel": "RealityDevice17,1",
                    "osName": "visionOS",
                    "osVersion": "26.5.23O471",
                }
            }),
            Client::Ios => json!({
                "client": {
                    "clientName": "IOS",
                    "clientVersion": "21.26.4",
                    "deviceMake": "Apple",
                    "deviceModel": "iPhone16,2",
                    "osName": "iPhone",
                    "osVersion": "18.3.2.22D82",
                }
            }),
            Client::AndroidVr => json!({
                "client": {
                    "clientName": "ANDROID_VR",
                    "clientVersion": "1.65.10",
                    "deviceMake": "Oculus",
                    "deviceModel": "Quest 3",
                    "androidSdkVersion": 32,
                    "osName": "Android",
                    "osVersion": "12L",
                }
            }),
            Client::TvDowngraded => json!({
                "client": {
                    "clientName": "TVHTML5",
                    "clientVersion": "5.20260707",
                }
            }),
        }
    }

    pub fn user_agent(self) -> &'static str {
        match self {
            Client::VisionOs => {
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
            }
            Client::Ios => {
                "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)"
            }
            Client::AndroidVr => {
                "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"
            }
            Client::TvDowngraded => "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version",
        }
    }
}

pub const TRY_ORDER: [Client; 4] = [
    Client::VisionOs,
    Client::Ios,
    Client::AndroidVr,
    Client::TvDowngraded,
];
