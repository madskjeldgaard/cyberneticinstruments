/*
 _   _                            _            
| |_| |__   ___  __   _____  _ __| |_ _____  __
| __| '_ \ / _ \ \ \ / / _ \| '__| __/ _ \ \/ /
| |_| | | |  __/  \ V / (_) | |  | ||  __/>  < 
 \__|_| |_|\___|   \_/ \___/|_|   \__\___/_/\_\
                                               
A cybernetic polyvoice reel to reel emulator matrix mixer / feedback system / looping delay

Dependencies:
- Sleet
- Modality
- Influx

Specs: 
- one sound input (from a modular synth for example)
- sound going into 8 voices
- each voice has a time machine buffer looper/recorder at the end of an fx chain 
- The input of each voice is a matrix mixer with the input and all voices' outputs


IDEAS:
- "Layers" of control data flow between the Influx and the synths? IE. influx controlling a bunch of LFO's controlling the Synths


*/
(
	q = q ?? ();

	q.numVoices = 8;
	q.numOutputChans = 2;
	q.controllerChoice = "korg-nanokontrol2";

	q.excludeParams = [
		'record',
		'jumpToStart',
		'buffer',
		'type', // filter
		'level', // limiter
		'in',
		'inVol',
		'wet1002', // Leakdc
		'wet1003', // limiter
		'wet1004', // voicevolume
		'voicevolume'

	];

	q.init = {|self|

		fork{

			// FX system
			self.sleet = Sleet.new(self.numOutputChans);
			s.sync;

			// Set up voices' sound sources
			self.makeVoices.value;
			s.sync;

			// Make mixers - each voice get's a "mix" parameter per mix in voice (using nodeproxy roles)
			self.makeMixers.value;
			s.sync;

			self.modality = self.modality ?? MKtl('cyber1', self.controllerChoice);
			s.sync;

			self.setupController.value;
			s.sync;

			self.addTimemachine.value;
			s.sync;

			self.addFx.value;
			s.sync;

			self.voices.do{|voice|
				self.addSpecs(voice);
			};
			s.sync;

			// self.voices.do{|v| v.lag(\timerate, 1)};
			self.voices.do{|v| 
				var lagtime=1;
				var params = self.modulateAbleparams(v);

				params = params.collect{|p| [p, lagtime]}.flatten;

				v.lag(*params)
			};

			self.setupFluxi.value;
			s.sync;

			self.makeEnvs.value;

			self.constrainOutputsToEnvs.value;

			Tdef(\blink, { 
				var newVal, button, pat; 
				button = self.modality.elAt('tr', 'cycle');
				pat = Pseq([1, 0.25, 0.125], inf).asStream;

				loop{
					pat.next.wait;  

					if(
						button.value == 1.0, { 
							newVal = 0 
						}, { 
							newVal = 1 
						}
					);

					button.value_(newVal)
				}
			}).play;

		}
	};

	// Temporary hack (hopefully)
	q.addSpecs = {|self, voice| 
		var params = self.modulateAbleparams(voice);

		params.do{|p|
			voice.addSpec(p, [0.0, 1.0, \lin])
		}
	};

	q.modulateAbleparams = {|self, voice|
		var vox = voice;
		var forbiddenParams = self.excludeParams;

		// Filter out params that should not be modulated
		"vooix: %".format(vox).postln;
		vox.controlKeys.reject({|param| 
			forbiddenParams.indexOfEqual(param).isNil.not
		})
	};

	q.setupFluxi = {|self| 

		self.fluxi = self.numVoices.collect{|fluxNum|

			"Creating flux num %".format(fluxNum).postln;

			Influx.new(
				ins: 2,  
				outs: 64
			);
		};

		self.fluxi.do{|thisFlux, fluxNum|
			var thisVoice = self.voices[fluxNum];
			var params = self.modulateAbleparams(thisVoice);
			// "thisflux: %, fluxnum: %, thisvoice: %, params: %".format(thisFlux, fluxNum, thisVoice, params).postln;

			thisFlux.attachMapped(
				thisVoice,
				paramNames: params
			)
		};

	};

	q.makeEnv = { |self, numSteps = 8, rand = 1.0, maxCurve = 3.0|
		var numTimes = numSteps.max(2).round(2).asInteger;
		var levels = (numTimes + 1).collect { |i| 1.0.rand2.blend( (i / numTimes).unibi, 1-rand) };
		// bit boring to have them regular
		var times = (1/numTimes).dup(numTimes);
		var curves = numTimes.collect { maxCurve.rand2 };
		// put in fixed values
		levels[0] = -1;
		levels[numTimes div: 2] = 0;
		levels[numTimes] = 1;
		Env(levels, times, curves);
	};

	q.makeEnvs = {|self|
		self.envs = self.fluxi.collect{q.makeEnv.value(numSteps: 8, rand: 1.0, maxCurve: 10)}
	};

	q.constrainOutputsToEnvs = {|self|
		self.fluxi.do{|flux, fluxnum|
			flux.addProc(\base, {|val|
				self.envs[fluxnum].at(val)
			})
		};
	};

	// Wrap the output of a Flux to the trajectory of an enveloep
	q.envelopeRemapFlux = {|self| 

	};

	q.addFx = {|self|
		var baseIndex = self.numVoices;

		self.voices.do{|thisvoice|


			thisvoice[baseIndex+1] = \kfilter -> self.sleet.get('ring');
			thisvoice[baseIndex+2] = \kfilter -> self.sleet.get('pitchshift');
			thisvoice[baseIndex+3] = \kfilter -> self.sleet.get('freqshift');
			thisvoice[baseIndex+4] = \kfilter -> self.sleet.get('delay');
			thisvoice[baseIndex+5] = \kfilter -> self.sleet.get('chorus');
			thisvoice[baseIndex+6] = \kfilter -> self.sleet.get('filter');
			thisvoice[baseIndex+7] = \kfilter -> self.sleet.get('flanger');
			thisvoice[baseIndex+8] = \kfilter -> self.sleet.get('octer');
			thisvoice[baseIndex+9] = \kfilter -> self.sleet.get('freeverb');
			thisvoice[baseIndex+10] = \kfilter -> self.sleet.get('triode');
			thisvoice[baseIndex+11] = \kfilter -> self.sleet.get('waveloss');


			thisvoice[1002] = \filterIn -> {|in| LeakDC.ar(in).tanh};
			thisvoice[1003] = \filter -> self.sleet.get('limiter');
			thisvoice[1004] = \filter -> {|in, voicevolume=0.1| 
				in * voicevolume
			};

			// Limiter level
			thisvoice.set(\level, 0.75,  \voicevolume, 0.25);

		}
	};

	q.addTimemachine = {|self|
		self.voices.do{|thisvoice|
			thisvoice[1001] = \filter -> self.sleet.get('timemachine');

			thisvoice.lag(\timerate, 0.1);
			thisvoice.set(\timerate, rrand(0.0,1.0), \record, 0.0);
		}
	};

	q.makeVoices = {|self|
		self.voices = self.numVoices.collect{|voxnum| 
			var voicename = "voice%".format(voxnum).asSymbol;

			// Define the source of the voice
			Ndef(voicename).source = {|in=#[ 0, 1 ], inVol=0.4|

			SoundIn.ar(in, inVol)
		};

		// Make sure voice is audio and the right amount of channels
		Ndef(voicename).mold(self.numOutputChans, 'audio');

	}
};

q.makeMixers = {|self|

	self.numVoices.do{|voxnum|

		// Mix in all other voices (rejecting this one)
		(0..self.numVoices-1).reject({|i| i == voxnum}).do{|otherVoxNum, index|
			var thisVoice = "voice%".format(voxnum).asSymbol;
			var mixinVoice = "voice%".format(otherVoxNum).asSymbol;

			index = index + 1; // Start from 1 to not overwrite source

			Ndef(thisVoice)[index] = \mix -> { Ndef(mixinVoice).ar };

			// Set mix in parameter to 0 by default 
			Ndef(thisVoice).set("mix%".format(index).asSymbol, 0)
		};
	}
};

q.setupController = {|self| 
	var sliders = self.modality.elAt('sl');
	var knobs = self.modality.elAt('kn');
	var rButtons = self.modality.elAt('bt', 'R');
	var sButtons = self.modality.elAt('bt', 'S');
	var mButtons = self.modality.elAt('bt', 'M');

	// Play voice
	sButtons.do{|but, buttonNum|
		but.action_({|el|
			var val = el.value;
			var targetVoice = self.voices[buttonNum % self.voices.size];

			
			if(targetVoice.isMonitoring, {
				"Setting play state of voice % to stopped".format(targetVoice, val).postln;

				// Toggle led
				el.value_(0); 

				targetVoice.stop;
			}, {
				"Setting play state of voice % to playing".format(targetVoice, val).postln;

				// Toggle led
				el.value_(1); 

				targetVoice.play;
			})
		})
	};


	// Record buttons
	rButtons.do{|but, buttonNum|
		but.action_({|el|
			var val = el.value;
			var targetVoice = self.voices[buttonNum % self.voices.size];

			// Toggle led
			el.value_(val); 

			"Setting record of voice % to %".format(targetVoice, val).postln;

			targetVoice.set(\record, val)

		})
	};

	// Sliders
	sliders.do{|slider, sliderNum|
		slider.action_({|el|
			var val = el.value;
			var targetVoice = self.voices[sliderNum % self.voices.size];
			var targetFlux = self.fluxi[sliderNum % self.fluxi.size];

			// "Setting rate of voice % to %".format(targetVoice, val).postln;

			// targetVoice.set(\timerate, val)

			targetFlux.set(\x, val.linlin(0.0,1.0,-1.0,1.0))

		})
	};

	// Knobs
	knobs.do{|knob, knobNum|
		knob.action_({|el|
			var val = el.value;
			var targetVoice = self.voices[knobNum % self.voices.size];
			var targetFlux = self.fluxi[knobNum % self.fluxi.size];

			// targetVoice.set(\timerate, val)

			targetFlux.set(\y, val.linlin(0.0,1.0,-1.0,1.0))

		})
	};


	// Reset all buttons
	(rButtons ++ sButtons ++ mButtons).do{|b| 
		b.value_(0)
	};

	self.modality.elAt('tr', 'rec').action_({|el|
		el.value_(1);
		s.record
	});

	self.modality.elAt('tr', 'stop').action_({|el|
		s.stopRecording;
		self.modality.elAt('tr', 'rec').value_(0)
	})

};

q.init.value

)

q.modality.gui
