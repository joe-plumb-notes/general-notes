@RestController
public class Application {
        @RequestMapping("/")
        public String hello() {
            return "Hello der!"
        }
}