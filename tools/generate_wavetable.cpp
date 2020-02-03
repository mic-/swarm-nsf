/**
 * Generate a table of bandlimited pulse waves in 8-bit unsigned PCM format,
 * as well as an index that maps NES pulse wave period values to the correct
 * wave table entry.
 *
 * /Mic, 2020
 */
#include <array>
#include <cmath>
#include <cstdio>
#include <vector>

constexpr double SAMPLE_RATE = 32768.0;
constexpr double NYQVIST = (SAMPLE_RATE / 2.0);
constexpr double CPU_CLOCK = 1789773.0;
constexpr size_t SEMITONES_PER_WAVEFORM = 6;
constexpr size_t TOTAL_SEMITONES = 96;
constexpr size_t TOTAL_WAVEFORMS = (TOTAL_SEMITONES / SEMITONES_PER_WAVEFORM);
constexpr size_t WAVEFORM_LENGTH = 128;
constexpr double PI = 3.14159265;
constexpr double C1_FREQ = 32.703;
constexpr double G1_FREQ = 48.999;
constexpr double B8_FREQ = 7902.1;

const std::array<double, 4> DUTY_CYCLES = {0.125, 0.25, 0.5, 0.75};


void print_table(const std::vector<uint8_t>& table, FILE *fp)
{
    for (int i = 0; i < table.size(); ++i)
    {
        if ((i % 16) == 0) fputs("\n.byte ", fp);
        fprintf(fp, "0x%02X", table[i]);
        if (((i % 16) != 15) && i != table.size()-1) fputs(", ", fp);
    }
}


std::vector<uint8_t> generate_wavetable(const double duty_cycle)
{
    static const double INTERVAL_RATIO = pow(2.0, SEMITONES_PER_WAVEFORM/12.0);
    std::vector<uint8_t> wave_table;
    
    for (size_t w = 0; w < TOTAL_WAVEFORMS; ++w)
    {
        double f = G1_FREQ * pow(INTERVAL_RATIO, w);
        const size_t harmonics = (NYQVIST / f);
        double sample_max = 0;
        double sample_min = 1000000.0;
        std::vector<double> waveform;

        for (size_t s = 0; s < WAVEFORM_LENGTH; ++s)
        {
            double sample = duty_cycle;
            for (size_t h = 1; h <= harmonics; ++h)
            {
                double gibbs = cos((h-1)*PI / (2.0*harmonics));
                gibbs *= gibbs;
                sample += gibbs * (2 / (h*PI)) * sin(PI*h*duty_cycle) * cos(2.0*PI*h*s/WAVEFORM_LENGTH);
            }

            if (sample > sample_max) sample_max = sample;
            if (sample < sample_min) sample_min = sample;
            waveform.push_back(sample);
        }

        for (size_t s = 0; s < WAVEFORM_LENGTH; ++s)
        {
            double sample = (waveform[s] - sample_min) / (sample_max - sample_min);
            sample = round(sample * 255.0);
            if (sample < 0) sample = 0;
            else if (sample > 255.0) sample = 255;

            waveform[s] = static_cast<uint8_t>(sample);
        }

        std::copy(waveform.begin(), waveform.end(), std::back_inserter(wave_table));
    }
    return wave_table;
}


std::vector<uint8_t> generate_index()
{
    static const double INTERVAL_RATIO = pow(2.0, SEMITONES_PER_WAVEFORM/12.0);
    std::vector<uint8_t> index;

    for (size_t period = 0; period < 0x800; ++period)
    {
        const double f = CPU_CLOCK / (16.0 * (period + 1));
        size_t interval = 0;
        if (f < C1_FREQ)
        {
            interval = 0;
        } else if (f > B8_FREQ)
        {
            interval = TOTAL_WAVEFORMS-1;
        } else
        {
            double m = 1;
            for (size_t i = 0; i < TOTAL_WAVEFORMS; ++i)
            {
                if (f >= C1_FREQ*m && f < C1_FREQ*m*INTERVAL_RATIO)
                {
                    interval = i;
                    break;
                }
                m *= INTERVAL_RATIO;
            }
        }
        index.push_back(interval);
    }
    return index;
}

int main()
{
    FILE *fp = fopen("wave_table.s", "wb");
    fputs(".globl wave_table\nwave_table:", fp);
    for (const auto duty_cycle : DUTY_CYCLES)
    {
        fprintf(fp, "\n@ %1.2f%%", duty_cycle * 100.0);
        print_table(generate_wavetable(duty_cycle), fp);
    }
    fclose(fp);

    fp = fopen("wave_table_index.s", "wb");
    fputs(".globl wave_table_index\nwave_table_index:", fp);
    print_table(generate_index(), fp);
    fclose(fp);
}
