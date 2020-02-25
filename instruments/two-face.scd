/*
 _                        __                
| |___      _____        / _| __ _  ___ ___ 
| __\ \ /\ / / _ \ _____| |_ / _` |/ __/ _ \
| |_ \ V  V / (_) |_____|  _| (_| | (_|  __/
 \__| \_/\_/ \___/      |_|  \__,_|\___\___|
                                            

a schizoincestoid game pad instrument

*/
(
	~ff = ~ff ?? ();

	~ff.init = {|self|
		self.mktl = MKtl('gamepad1', "shanwan_ps3");
		self.sleet = self.sleet ?? Sleet.new(self.numVoiceChans);

		self.buffer = Buffer.alloc(s, s.sampleRate * 16,  numChannels: self.numVoiceChans);

		// Map outputs of joystick to x/y of Influx
		self.mapToFlux.value;

		// Make the two voices
		self.setupVoices.value;

		// Add output processing to Influx
		self.makeEnvs.value;
		self.addProcessingToInfluxes.value;

		// Add named shortcuts for elements in the mktl
		self.renameElements.value;

		// Map using preset 1
		self.mappings['preset1'].keysValuesDo{|el, actionName|
			"Mapping % to %".format(el, actionName).postln;
			self.mktl.elAt(el).action = self.actions[actionName]
		};
	};

	~ff.numVoiceChans = 2; 

	~ff.ignoreParams = [
		\in,
		\vca,
		\volume, \gain, \inGain, \ingain,
		\wet100, \wet101, \wet102, \wet103, \wet104 // vca, pan, volume, leakdc 
	];

	~ff.mapToFlux = {|self|

		['x', 'y'].do{|axis|
			// Left
			self.mktl.elAt('joy','l', axis).action = {|el|
				var val = el.value.unibi; // Bipolar out for Influx 
				self.voices[\left].influx.set(axis, val)
			};

			// Right
			self.mktl.elAt('joy','r', axis).action = {|el|
				var val = el.value.unibi; // Bipolar out for Influx 
				self.voices[\right].influx.set(axis, val)
			};

		}
	};

	// From alberto de campo's Influx examples
	~ff.fluxEnv = { |q, numSteps = 7, rand = 1.0, maxCurve = 3.0|
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

	~ff.makeEnvs = {|self|
		self.voices.do{|voice|
			var numouts = voice.influx.outNames.size;

			voice[\envs] = numouts.collect{ self.fluxEnv } 
		}
	};

	~ff.addProcessingToInfluxes = {|self|
		self.voices.do{|voice|
			voice.influx.addProc(\base, { |val, i|
				voice[\envs][i].at(val.tanh.biuni).biuni;
			})
		}
	};

	~ff.actions = {|self|

		(
			openVCAL: {|el| self.voices[\left].ndef.set(\vca, el.value) },
			openVCAR: {|el| self.voices[\right].ndef.set(\vca, el.value) },

			nextSoundL: {|el| },
			nextSoundR: {|el| },
			prevSoundL: {|el| },
			prevSoundR: {|el| },

			randWeightL: {|el| self.voices[\left].influx.rand },
			randWeightR: {|el| self.voices[\right].influx.rand },

		)
	};

	~ff.renameElements = {|self|
		self.mktl.addNamed(\l1, self.mktl.elAt('bt', 'l1'));
		self.mktl.addNamed(\l2, self.mktl.elAt('bt', 'l2'));

		self.mktl.addNamed(\r1, self.mktl.elAt('bt', 'r1'));
		self.mktl.addNamed(\r2, self.mktl.elAt('bt', 'r2'));

	};

	~ff.mappings = (
		preset1: (
			\l1: \openVCAL,
			\r1: \openVCAR,
			\l2: \randWeightL,
			\r2: \randWeightR,
		)
	);

	~ff.setupVoices = {|self|
	
		// Setup voices
		self.voices = ();

		[\left, \right].do{|voxname|
			var ndefname = "twoface_%".format(voxname).asSymbol;
			var thisvoice;

			self.voices[voxname] = ();

			// Influx for this voice
			self.voices[voxname].influx = Influx.new(2, 128);

			// Setup the basic nodeproxy
			thisvoice = Ndef(ndefname).clear;
			thisvoice.play;
			thisvoice.mold(self.numVoiceChans, 'audio');

			thisvoice.source = self.soundProcesses[\sources][\default];

			// Add a few nice basic effects
			// thisvoice[1] = \filter -> self.sleet.get('chorus');
			thisvoice[2] = \filter -> self.sleet.get('pitchshift');
			thisvoice[3] = \filter -> self.sleet.get('freqshift');
			thisvoice[4] = \filter -> self.sleet.get('delay');
			thisvoice[5] = \filter -> self.sleet.modules[\spectral].choose;
			thisvoice[6] = \filter -> self.sleet.get('octer');
			// thisvoice[7] = \filter -> self.sleet.get('waveloss');

			thisvoice[8] = \filter -> self.sleet.get('timemachine_ext');
			// thisvoice[5] = \filter -> self.sleet.get('scramble');
			// thisvoice[7] = \filter -> self.sleet.get('triode');
			// thisvoice[8] = \filter -> self.sleet.get('ring');

			// Plumming
			thisvoice[100] = \filter -> self.soundProcesses[\vca];
			thisvoice[101] = \filter -> self.soundProcesses[\pan];
			thisvoice[102] = \filter -> self.soundProcesses[\volume];
			thisvoice[103] = \filter -> self.soundProcesses[\leak];
			thisvoice[105] = \filter -> self.soundProcesses[\limiter];

			thisvoice.set(\pan, 1.rand, \buffer, self.buffer.bufnum);

			// Finally attach the voice to Influx
			self.voices[voxname].influx.attachMapped(
				thisvoice, 
				paramNames: thisvoice.controlKeys(except: self.ignoreParams)
			);

			self.voices[voxname].ndef = thisvoice;
		};

		// Attach voices to Influx
		// self.voices[]

	};

	~ff.soundProcesses = (
		/*
			
		Design principles for sound sources:

		- Make them stereo

		*/
		sources: (
			default: {|freq=444, detune=1, width=0.5, lfofreq=1, noise=0.5| 
				var sig = VarSaw.ar(
					freq: ([freq, freq-detune]*LFSaw.kr(freq/10*noise).linlin(-1.0,1.0,1.0,1.1)).wrap(50,500), 
					iphase: 0, 
					width: width * LFSaw.kr(lfofreq).linlin(-1.0,1.0,0.0,1.0)
				);

				sig
			},
		),
		vca: {|in, vca=0, vcarelease=0.5| 
			in*EnvGen.kr(Env.asr(0.001,1.0,vcarelease), vca)
		},
		pan: {|in, pan=0| 
			Balance2.ar(in[0], in[1], pan.linlin(0.0,1.0,-1.0,1.0))
		},
		volume: {|in, volume=0.75|
			in * volume
		},
		leak: {|in|
			LeakDC.ar(in,  coef: 0.995,  mul: 1.0,  add: 0.0)
		},
		limiter: {|in|
			in.tanh
		}
	);

	~ff.init.value;
)

s.meter;

z = Sleet.new

z.postInfo
