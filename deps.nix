# generated manually based on build.zig.zon

{ linkFarm, fetchzip }:

linkFarm "zig-packages" [
  {
    name = "webui-2.5.0-beta.4-pxqD5esSNwCHzwq6ndnW-ShzC_nPNAzGu13l4Unk0rFl";
    path = fetchzip {
      url = "https://github.com/webui-dev/webui/archive/699119f42fc64ae42c9121bc4749b740f71949af.tar.gz";
      hash = "sha256-L3K/0F8k1wd+ASmI7O5iVKiPo7vVPDfbeoTv/0dxF0E=";
    };
  }
  {
    name = "ghostty-1.1.4-5UdBC49Q9QIhEpOaAYni2oEs7vFlVUQ_chpVl9VFAJQM";
    path = fetchzip {
      url = "https://github.com/ghostty-org/ghostty/archive/b46673e63151f495c973d3043bf20612f80deda0.tar.gz";
      hash = "sha256-NYeQIpFu4gHrEo+gcvTgBvLyIQnUDgeiMNTtJDHUl+c=";
    };
  }
]