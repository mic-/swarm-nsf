/**
 * Generates the palette data for the VU meters in the SwarmNSF visualizer.
 * /Mic, 2020
 */
 
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <functional>

struct RGB
{
    RGB(double r, double g, double b) : red(r), green(g), blue(b) {}

    uint16_t as_packed_RGB5()
    {
        uint16_t r = red * 31;
        uint16_t g = green * 31;
        uint16_t b = blue * 31;
        return r | (g << 5) | (b << 10);
    }
    
    friend RGB operator+(RGB lhs, double rhs)
    {
        lhs.red += rhs;
        lhs.green += rhs;
        lhs.blue += rhs;
        return lhs;
    }
  
    static RGB from_HSV(double H, double S, double V)
    {
        const double C = V * S;
        const double X = C * (1 - fabs(fmod(H / 60, 2) - 1));
        const double m = V - C;

        RGB rgb{0, 0, 0};

        if (H < 60)
        {
            rgb = RGB{C, X, 0};
        } else if (H < 120)
        {
            rgb = RGB{X, C, 0};
        } else if (H < 180)
        {
            rgb = RGB{0, C, X};
        } else if (H < 240)
        {
            rgb = RGB{0, X, C};
        } else if (H < 300)
        {
            rgb = RGB{X, 0, C};
        } else if (H < 360)
        {
            rgb = RGB{C, 0, X};
        }

        return rgb + m;
    }

    double red;
    double green;
    double blue;
};


void print_table(const char *name, std::function<RGB(int)> calc)
{
    printf("static uint16_t %s[16] = {", name);
    for (int i = 0; i < 16; ++i) {
        printf("%d", calc(i).as_packed_RGB5());
        if (i != 15) printf(", ");
    }
    printf("};\n");
}


int main()
{
    print_table("volume_bar_on", [] (int i) {
        return RGB::from_HSV(120 - (i*120.0/15), 1, 1);
    });

    print_table("volume_bar_half", [] (int i) {
        return RGB::from_HSV(120 - (i*120.0/15), 1, 0.7);
    });

    print_table("volume_bar_off", [] (int i) {
        return RGB::from_HSV(120 - (i*120.0/15), 1, 0.3333);
    });

    print_table("cpu_bar_on", [] (int i) {
        return RGB::from_HSV(240 + (i*119.0/15), 1, 1);
    });

    print_table("cpu_bar_half", [] (int i) {
        return RGB::from_HSV(240 + (i*119.0/15), 1, 0.68);
    });

    print_table("cpu_bar_off", [] (int i) {
        return RGB::from_HSV(240 + (i*119.0/15), 1, 0.3333);
    });
}
