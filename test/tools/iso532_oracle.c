/************************************************************************/
/*  iso532_oracle - reference-data generator for the SQAT test suite.    */
/*                                                                      */
/*  Thin driver around the UNMODIFIED ISO 532-1:2017 Annex A.4          */
/*  reference library (ISO_532-1.c / ISO_532-1.h). It calibrates an     */
/*  input WAV exactly as SQAT's calibrate.m does, calls the reference   */
/*  implementation, and writes the result as CSV for use as golden      */
/*  data by the MATLAB tests.                                          */
/*                                                                      */
/*  The ISO reference sources are NOT vendored here: they ship with the */
/*  standard and are not ours to redistribute. Point ISO_SRC at your    */
/*  copy to rebuild the golden data (see Makefile). The generated CSVs  */
/*  in test/golden/ are committed so the test suite runs without them.  */
/*                                                                      */
/*  Usage:                                                              */
/*    iso532_oracle tv  <sig.wav> <cal.wav> <cal_dB> <out.csv>          */
/*        time-varying total loudness N(t), on the 500 Hz output grid   */
/*    iso532_oracle tvb <sig.wav> <cal.wav> <cal_dB> <bark> <out.csv>   */
/*        time-varying specific loudness N'(z0,t) at one Bark band, on  */
/*        the same grid. This mirrors what Annex B.4 tabulates: a       */
/*        single band per test signal (2.5, 8.5 or 17.5 Bark).          */
/*    iso532_oracle st  <sig.wav> <cal.wav> <cal_dB> <skip> <out.csv>   */
/*        stationary loudness from a signal, single value               */
/*    iso532_oracle stp <sig.wav> <cal.wav> <cal_dB> <skip> <out.csv>   */
/*        stationary specific loudness pattern, 240 values (Annex B.3)  */
/*    iso532_oracle lv  <levels.txt> <out.csv>                          */
/*        stationary loudness from 28 third-octave levels               */
/*    iso532_oracle lvp <levels.txt> <out.csv>                          */
/*        stationary specific loudness pattern from those levels        */
/*                                                                      */
/*  Add D as a trailing argument to any subcommand for diffuse field.   */
/************************************************************************/

#include "ISO_532-1.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

/*  Rate to which the reference main program downsamples the summed loudness
    for output. Defined in the ISO Annex A.4 ISO_532-1_main.c, not in the
    library header, so it is repeated here.                                */
#define SR_LOUDNESS 500

/*  ---------------------------------------------------------------- */
/*  Minimal WAV reader: mono/stereo, 16-bit PCM or 32-bit IEEE float. */
/*  Stereo takes channel 1, matching the standard's "one channel"    */
/*  requirement and audioread(...,1) on the MATLAB side.             */
/*  ---------------------------------------------------------------- */
static int rd_wav(const char *path, double **out, int *n, double *sr)
{
    FILE *f = fopen(path, "rb");
    unsigned char h[8], b[16];
    char id[5] = {0};
    int bits = 0, ch = 0, i;
    long rate = 0;

    if (!f) { fprintf(stderr, "iso532_oracle: cannot open %s\n", path); return -1; }
    if (fseek(f, 12, SEEK_SET) != 0) { fclose(f); return -1; }   /* RIFF....WAVE */

    for (;;)
    {
        unsigned int sz;
        if (fread(h, 1, 8, f) != 8) { fclose(f); return -1; }
        memcpy(id, h, 4);
        sz = h[4] | (h[5] << 8) | (h[6] << 16) | ((unsigned)h[7] << 24);

        if (!strcmp(id, "fmt "))
        {
            if (fread(b, 1, 16, f) != 16) { fclose(f); return -1; }
            ch   =  b[2] | (b[3] << 8);
            rate =  b[4] | (b[5] << 8) | (b[6] << 16) | ((long)b[7] << 24);
            bits = b[14] | (b[15] << 8);
            if (sz > 16) fseek(f, (long)sz - 16, SEEK_CUR);
        }
        else if (!strcmp(id, "data"))
        {
            int ns = (int)(sz / (unsigned)(bits / 8) / (unsigned)ch);
            double *d = (double*)malloc(sizeof(double) * (size_t)ns);
            if (!d) { fclose(f); return -1; }
            for (i = 0; i < ns; i++)
            {
                if (bits == 16) { short v; if (fread(&v,2,1,f)!=1) break; d[i] = v / 32768.0; }
                else            { float v; if (fread(&v,4,1,f)!=1) break; d[i] = v; }
                if (ch == 2) fseek(f, bits / 8, SEEK_CUR);   /* skip channel 2 */
            }
            fclose(f);
            *out = d; *n = ns; *sr = (double)rate;
            return 0;
        }
        else fseek(f, (long)sz + (sz & 1), SEEK_CUR);
    }
}

/*  Calibration factor, identical to SQAT utilities/calibrate.m:
    CalFactor = sqrt( 10^(L/10) * I_REF / mean(ref^2) )                */
static double cal_factor(const double *ref, int n, double level_dB)
{
    double ms = 0; int i;
    for (i = 0; i < n; i++) ms += ref[i] * ref[i];
    return sqrt(pow(10.0, level_dB / 10.0) * I_REF / (ms / n));
}

/*  Read 28 third-octave levels; "<f> : <level>" per line, # = comment  */
static int rd_levels(const char *path, double *lvl)
{
    FILE *f = fopen(path, "r");
    char line[256];
    int k = 0;
    if (!f) { fprintf(stderr, "iso532_oracle: cannot open %s\n", path); return -1; }
    while (fgets(line, sizeof line, f) && k < N_LEVEL_BANDS)
    {
        char *c = strchr(line, ':');
        if (line[0] == '#' || !c) continue;
        lvl[k++] = atof(c + 1);
    }
    fclose(f);
    if (k != N_LEVEL_BANDS)
    {
        fprintf(stderr, "iso532_oracle: expected %d levels, got %d\n", N_LEVEL_BANDS, k);
        return -1;
    }
    return 0;
}

/*  Specific loudness pattern for a single time frame: 240 values.
    This is what Annex B.3 tabulates for stationary signals.            */
static void wr_pattern(const char *path, double *S[N_BARK_BANDS], int frame)
{
    FILE *o; int b;
    o = fopen(path, "w");
    fprintf(o, "bark,Nprime\n");
    for (b = 0; b < N_BARK_BANDS; b++)
        fprintf(o, "%.1f,%.8f\n", (b + 1) / 10.0, S[b][frame]);
    fclose(o);
}

/*  Specific loudness at one Bark band versus time, on the SR_LOUDNESS
    grid. Annex B.4 tabulates exactly this - one band per test signal -
    rather than the full 240-by-time matrix, which would be enormous.   */
static void wr_band(const char *path, double *S[N_BARK_BANDS],
                    int nt, double bark)
{
    FILE *o; int t, dec = SR_LEVEL / SR_LOUDNESS;
    int b = (int)(bark * 10.0 + 0.5) - 1;          /* 0.1 Bark -> index 0 */
    if (b < 0) b = 0;
    if (b > N_BARK_BANDS - 1) b = N_BARK_BANDS - 1;
    o = fopen(path, "w");
    fprintf(o, "t,Nprime_at_%.1fBark\n", (b + 1) / 10.0);
    for (t = 0; t < nt; t += dec)
        fprintf(o, "%.4f,%.8f\n", t / (double)SR_LEVEL, S[b][t]);
    fclose(o);
}

int main(int argc, char **argv)
{
    double *N = NULL, *S[N_BARK_BANDS];
    double bark = 0;
    int i, ret, field = SoundFieldFree;
    int wantPattern = 0, wantBand = 0;
    const char *mode, *out = NULL;

    if (argc < 3) { fprintf(stderr, "usage: see header of %s\n", __FILE__); return 2; }
    mode = argv[1];
    for (i = 1; i < argc; i++) if (!strcmp(argv[i], "D")) field = SoundFieldDiffuse;

    wantPattern = (!strcmp(mode, "stp") || !strcmp(mode, "lvp"));
    wantBand    = !strcmp(mode, "tvb");

    if (!strncmp(mode, "lv", 2))                    /* ---- from levels ---- */
    {
        double lvl[N_LEVEL_BANDS], *TOL[N_LEVEL_BANDS];
        if (argc < 4) { fprintf(stderr, "usage: %s <levels.txt> <out.csv>\n", mode); return 2; }
        if (rd_levels(argv[2], lvl)) return 1;
        out = argv[3];

        for (i = 0; i < N_LEVEL_BANDS; i++) TOL[i] = &lvl[i];
        N = (double*)calloc(1, sizeof(double));
        for (i = 0; i < N_BARK_BANDS; i++) S[i] = (double*)calloc(1, sizeof(double));
        ret = f_loudness_from_levels(TOL, 1, field, LoudnessMethodStationary, N, S);
    }
    else                                            /* ---- from signal ---- */
    {
        double *sig, *cal, sr, csr, k, skip = 0;
        int ns, nc, meth, nlev;
        struct InputData in;

        if (argc < 6) { fprintf(stderr, "usage: see header of %s\n", __FILE__); return 2; }
        if (rd_wav(argv[2], &sig, &ns, &sr))  return 1;
        if (rd_wav(argv[3], &cal, &nc, &csr)) return 1;

        k = cal_factor(cal, nc, atof(argv[4]));
        for (i = 0; i < ns; i++) sig[i] *= k;

        in.NumSamples = ns; in.SampleRate = sr; in.pData = sig;

        if (!strncmp(mode, "st", 2))                /* st, stp */
        {
            meth = LoudnessMethodStationary;
            skip = atof(argv[5]);
            out  = argv[6];
            nlev = 1;
        }
        else if (wantBand)                          /* tvb <bark> <out> */
        {
            if (argc < 7) { fprintf(stderr, "usage: tvb <sig> <cal> <dB> <bark> <out.csv>\n"); return 2; }
            meth = LoudnessMethodTimeVarying;
            bark = atof(argv[5]);
            out  = argv[6];
            nlev = ns / (int)(sr / SR_LEVEL);
        }
        else                                        /* tv */
        {
            meth = LoudnessMethodTimeVarying;
            out  = argv[5];
            nlev = ns / (int)(sr / SR_LEVEL);
        }
        if (!out) { fprintf(stderr, "iso532_oracle: missing output path\n"); return 2; }

        N = (double*)calloc((size_t)nlev, sizeof(double));
        for (i = 0; i < N_BARK_BANDS; i++) S[i] = (double*)calloc((size_t)nlev, sizeof(double));

        ret = f_loudness_from_signal(&in, field, meth, skip, N, S, nlev);
    }

    if (ret < 0) { fprintf(stderr, "iso532_oracle: reference library error %d\n", ret); return 1; }

    if (wantPattern)                    /* 240-point specific loudness pattern */
    {
        wr_pattern(out, S, 0);
        fprintf(stderr, "iso532_oracle: %s -> %s (%d Bark bands)\n",
                mode, out, N_BARK_BANDS);
    }
    else if (wantBand)                  /* N'(z0,t) at one Bark band, 500 Hz */
    {
        wr_band(out, S, ret, bark);
        fprintf(stderr, "iso532_oracle: %s -> %s (%.1f Bark, %d samples @ %d Hz)\n",
                mode, out, bark, (ret + 3) / 4, SR_LOUDNESS);
    }
    else                                /* total loudness */
    {
        /*  Emitted on the SR_LOUDNESS = 500 Hz grid, which is what the ISO
            reference main program reports and what SQAT's OUT.time /
            OUT.InstantaneousLoudness use. Stationary is a single value.   */
        int dec = (ret > 1) ? (SR_LEVEL / SR_LOUDNESS) : 1;
        int nw  = 0;
        FILE *o = fopen(out, "w");
        if (!o) { fprintf(stderr, "iso532_oracle: cannot write %s\n", out); return 1; }
        fprintf(o, "t,N\n");
        for (i = 0; i < ret; i += dec, nw++)
            fprintf(o, "%.4f,%.8f\n", i / (double)SR_LEVEL, N[i]);
        fclose(o);
        fprintf(stderr, "iso532_oracle: %s -> %s (%d sample%s @ %d Hz)\n",
                mode, out, nw, nw == 1 ? "" : "s",
                (ret > 1) ? SR_LOUDNESS : 1);
    }
    return 0;
}
