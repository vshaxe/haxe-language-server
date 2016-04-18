package features;

class Feature {
    var context:Context;

    public function new(context) {
        this.context = context;
        init();
    }

    function init() {}
}