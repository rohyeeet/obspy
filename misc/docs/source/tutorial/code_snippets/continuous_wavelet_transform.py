import matplotlib.pyplot as plt
from obspy.core import read
import numpy as np
import mlpy

tr = read("http://examples.obspy.org/a02i.2008.240.mseed")[0]

omega0 = 8
wavelet_fct = "morlet"
scales = mlpy.wavelet.autoscales(N=len(tr.data), dt=tr.stats.delta, dj=0.05,
                                 wf=wavelet_fct, p=omega0)
spec = mlpy.wavelet.cwt(tr.data, dt=tr.stats.delta, scales=scales,
                        wf=wavelet_fct, p=omega0)
# approximate scales through frequencies
freq = (omega0 + np.sqrt(2.0 + omega0 ** 2)) / (4 * np.pi * scales[1:])

fig = plt.figure()
ax1 = fig.add_axes([0.1, 0.75, 0.7, 0.2])
ax2 = fig.add_axes([0.1, 0.1, 0.7, 0.60])
ax3 = fig.add_axes([0.83, 0.1, 0.03, 0.6])
t = np.arange(tr.stats.npts) / tr.stats.sampling_rate
ax1.plot(t, tr.data, 'k')
img = ax2.imshow(np.abs(spec), extent=[t[0], t[-1], freq[-1], freq[0]],
                 aspect='auto')
fig.colorbar(img, cax=ax3)
plt.show()
