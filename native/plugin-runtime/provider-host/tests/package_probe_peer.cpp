#include <iostream>
#include <string_view>

int main(int argc, char **argv) {
  if (argc == 1) {
    std::cout << "alpha 1 -> 2\nbeta 3 -> 4\n";
    return 0;
  }
  if (argc == 2 && std::string_view(argv[1]) == "-Qdtq") {
    std::cout << "orphan-one\n";
    return 0;
  }
  if (argc == 3 && std::string_view(argv[1]) == "-j" &&
      std::string_view(argv[2]) == "monitors") {
    std::cout << R"([{"name":"DP-1","width":1920,"height":1080,"x":0,"y":0,"focused":true,"reserved":[0,0,0,32],"activeWorkspace":{"id":4}},{"name":"HDMI-A-1","width":1280,"height":720,"x":1920,"y":0,"focused":false,"reserved":[0,0,0,0],"activeWorkspace":{"id":5}}])";
    return 0;
  }
  if (argc == 3 && std::string_view(argv[1]) == "-j" &&
      std::string_view(argv[2]) == "clients") {
    std::cout << R"([{"address":"0xsecret","title":"must-not-leak","at":[100,200],"size":[800,600],"workspace":{"id":4},"mapped":true,"hidden":false,"fullscreen":0},{"address":"0xother","at":[2000,20],"size":[400,300],"workspace":{"id":5},"mapped":true,"hidden":false,"fullscreen":0}])";
    return 0;
  }
  return 64;
}
