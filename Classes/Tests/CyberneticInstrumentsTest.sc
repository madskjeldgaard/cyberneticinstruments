CyberneticInstrumentsTest1 : UnitTest {
	test_check_classname {
		var result = CyberneticInstruments.new;
		this.assert(result.class == CyberneticInstruments);
	}
}


CyberneticInstrumentsTester {
	*new {
		^super.new.init();
	}

	init {
		CyberneticInstrumentsTest1.run;
	}
}
