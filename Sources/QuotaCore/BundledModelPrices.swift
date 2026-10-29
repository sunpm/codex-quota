// Pricing snapshot from models.dev (MIT), retrieved 2026-10-28.
// See Resources/ThirdPartyNotices/models-dev-LICENSE.txt.
import Foundation

public enum BundledModelPrices {
    public static let date = "2026-10-28"
    public static let data = Data(#"""
{
"openai":{"models":{
"gpt-3.5-turbo":{"cost":{"input":0.5,"output":1.5,"cache_read":0}},
"gpt-4":{"cost":{"input":30,"output":60}},
"gpt-4-turbo":{"cost":{"input":10,"output":30}},
"gpt-4.1":{"cost":{"input":2,"output":8,"cache_read":0.5}},
"gpt-4.1-mini":{"cost":{"input":0.4,"output":1.6,"cache_read":0.1}},
"gpt-4.1-nano":{"cost":{"input":0.1,"output":0.4,"cache_read":0.025}},
"gpt-4o":{"cost":{"input":2.5,"output":10,"cache_read":1.25}},
"gpt-4o-2024-05-13":{"cost":{"input":5,"output":15}},
"gpt-4o-2024-08-06":{"cost":{"input":2.5,"output":10,"cache_read":1.25}},
"gpt-4o-2024-11-20":{"cost":{"input":2.5,"output":10,"cache_read":1.25}},
"gpt-4o-mini":{"cost":{"input":0.15,"output":0.6,"cache_read":0.075}},
"gpt-5":{"cost":{"input":1.25,"output":10,"cache_read":0.125}},
"gpt-5-mini":{"cost":{"input":0.25,"output":2,"cache_read":0.025}},
"gpt-5-nano":{"cost":{"input":0.05,"output":0.4,"cache_read":0.005}},
"gpt-5-pro":{"cost":{"input":15,"output":120}},
"gpt-5.1":{"cost":{"input":1.25,"output":10,"cache_read":0.125}},
"gpt-5.2":{"cost":{"input":1.75,"output":14,"cache_read":0.175}},
"gpt-5.2-pro":{"cost":{"input":21,"output":168}},
"gpt-5.3-codex":{"cost":{"input":1.75,"output":14,"cache_read":0.175}},
"gpt-5.3-codex-spark":{"cost":{"input":1.75,"output":14,"cache_read":0.175}},
"gpt-5.4":{"cost":{"input":2.5,"output":15,"cache_read":0.25,"tiers":[{"input":5,"output":22.5,"cache_read":0.5,"tier":{"type":"context","size":272000}}],"context_over_200k":{"input":5,"output":22.5,"cache_read":0.5}}},
"gpt-5.4-mini":{"cost":{"input":0.75,"output":4.5,"cache_read":0.075}},
"gpt-5.4-nano":{"cost":{"input":0.2,"output":1.25,"cache_read":0.02}},
"gpt-5.4-pro":{"cost":{"input":30,"output":180,"tiers":[{"input":60,"output":270,"tier":{"type":"context","size":272000}}],"context_over_200k":{"input":60,"output":270}}},
"gpt-5.5":{"cost":{"input":5,"output":30,"cache_read":0.5,"tiers":[{"input":10,"output":45,"cache_read":1,"tier":{"type":"context","size":272000}}],"context_over_200k":{"input":10,"output":45,"cache_read":1}}},
"gpt-5.5-pro":{"cost":{"input":30,"output":180,"tiers":[{"input":60,"output":270,"tier":{"type":"context","size":272000}}],"context_over_200k":{"input":60,"output":270}}},
"gpt-5.6":{"cost":{"input":4,"output":20,"cache_read":0.4,"cache_write":5,"tiers":[{"input":8,"output":30,"cache_read":0.8,"cache_write":10,"tier":{"type":"context","size":272000}}],"context_over_200k":{"input":8,"output":30,"cache_read":0.8,"cache_write":10}}},
"gpt-5.6-luna":{"cost":{"input":0.2,"output":1.2,"cache_read":0.02,"cache_write":0.25,"tiers":[{"input":0.4,"output":1.8,"cache_read":0.04,"cache_write":0.5,"tier":{"type":"context","size":272000}}],"context_over_200k":{"input":0.4,"output":1.8,"cache_read":0.04,"cache_write":0.5}}},
"gpt-5.6-sol":{"cost":{"input":4,"output":20,"cache_read":0.4,"cache_write":5,"tiers":[{"input":8,"output":30,"cache_read":0.8,"cache_write":10,"tier":{"type":"context","size":272000}}],"context_over_200k":{"input":8,"output":30,"cache_read":0.8,"cache_write":10}}},
"gpt-5.6-terra":{"cost":{"input":2,"output":12,"cache_read":0.2,"cache_write":2.5,"tiers":[{"input":4,"output":18,"cache_read":0.4,"cache_write":5,"tier":{"type":"context","size":272000}}],"context_over_200k":{"input":4,"output":18,"cache_read":0.4,"cache_write":5}}},
"gpt-6-astra":{"cost":{"input":10,"output":50,"cache_read":1,"cache_write":12.5,"tiers":[{"input":20,"output":75,"cache_read":2,"cache_write":25,"tier":{"type":"context","size":272000}}],"context_over_200k":{"input":20,"output":75,"cache_read":2,"cache_write":25}}},
"gpt-6-luna":{"cost":{"input":0.1,"output":0.5,"cache_read":0.01,"cache_write":0.125,"tiers":[{"input":0.2,"output":0.75,"cache_read":0.02,"cache_write":0.25,"tier":{"type":"context","size":272000}}],"context_over_200k":{"input":0.2,"output":0.75,"cache_read":0.02,"cache_write":0.25}}},
"gpt-6-sol":{"cost":{"input":2,"output":10,"cache_read":0.2,"cache_write":2.5,"tiers":[{"input":4,"output":15,"cache_read":0.4,"cache_write":5,"tier":{"type":"context","size":272000}}],"context_over_200k":{"input":4,"output":15,"cache_read":0.4,"cache_write":5}}},
"gpt-6.1-sol":{"cost":{"input":2,"output":10,"cache_read":0.1,"cache_write":2.5,"tiers":[{"input":4,"output":15,"cache_read":0.2,"cache_write":5,"tier":{"type":"context","size":272000}}],"context_over_200k":{"input":4,"output":15,"cache_read":0.2,"cache_write":5}}},
"gpt-6.1-terra":{"cost":{"input":1,"output":5,"cache_read":0.05,"cache_write":1.25,"tiers":[{"input":2,"output":7.5,"cache_read":0.1,"cache_write":2.5,"tier":{"type":"context","size":272000}}],"context_over_200k":{"input":2,"output":7.5,"cache_read":0.1,"cache_write":2.5}}},
"gpt-daybreak-blue-latest":{"cost":{"input":4,"output":20,"cache_read":0.4,"cache_write":5,"tiers":[{"input":8,"output":30,"cache_read":0.8,"cache_write":10,"tier":{"type":"context","size":272000}}],"context_over_200k":{"input":8,"output":30,"cache_read":0.8,"cache_write":10}}},
"gpt-daybreak-red-latest":{"cost":{"input":12.5,"output":75,"cache_read":1.25,"cache_write":15.625}},
"o1":{"cost":{"input":15,"output":60,"cache_read":7.5}},
"o1-pro":{"cost":{"input":150,"output":600}},
"o3":{"cost":{"input":2,"output":8,"cache_read":0.5}},
"o3-mini":{"cost":{"input":1.1,"output":4.4,"cache_read":0.55}},
"o3-pro":{"cost":{"input":20,"output":80}},
"o4-mini":{"cost":{"input":1.1,"output":4.4,"cache_read":0.275}}
}}
}
"""#.utf8)
}
