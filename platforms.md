# DES
- power cap
	- default = current = 285W -> used as starting point
	- max = 300W
	- min = 100W

- benchmark settings
	- hf_Bert --it=600 --bs=16 		-> 280W 200s
	- resnet152 --it=800 --bs=32 		-> 200W 200s
	- opacus_cifar10 --it=4000 --bs=64 	-> 150W 200s


# APL18
- power cap: 
	- default = current = max = 600W
	- min = 400W

- benchmark settings
	- hf_Bert --it=1000 --bs=16 		-> 600W	200s
	- resnet152 --it=2500 --bs=32 		-> 500W 200s
	- opacus_cifar10 --it=1700 --bs=512	-> 430W 200s
				(bigger bs resulted in out of memory)
	
