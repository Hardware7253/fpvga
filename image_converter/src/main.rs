use image::io::Reader as ImageReader;
use image::{Rgb, ImageBuffer};
use std::fs::File;
use std::io::{Write, Error};

// Adapted from https://gist.github.com/timClicks/b0a19ab55c202b15a37abd852f4becc9

type Image = ImageBuffer<Rgb<u8>, Vec<u8>>;

fn main() -> Result<(), Box<dyn std::error::Error>>{

    
    // Resize image dimentsions
    let resize_x: u32 = read_string("Image resize width:").trim().parse().expect("Please input a number");
    let resize_y: u32 = read_string("Image resize height:").trim().parse().expect("Please input a number");

    // Input file name
    let binding = read_string("Input file name:");
    let file_name = binding.trim();
    let output_path = "image.hex"; // Output file path

    let channel_colour_combinations: u8 = 3; // Numbers of colours each rgb channel can hold, default is 255

    // Open image and resize;
    let img = ImageReader::open(file_name)?.decode()?;
    let img = img.to_rgb8();
    let resized_image = resize(&img, (resize_x, resize_y));
    let mut clamped_image = Image::new(resize_x, resize_y);

    // Clamp colours for preview and hex outputs
    for hex in [false, true] {
        for (x, y, pixel) in clamped_image.enumerate_pixels_mut() {
            if let Some(original_pixel) = resized_image.get_pixel_checked(x, y) {
                *pixel = clamp_colour(*original_pixel, channel_colour_combinations, hex);
            }
        }

        if hex {
            let _ = image_hex_dump(&clamped_image, channel_colour_combinations, output_path);
        } else {
            let _ = clamped_image.save("preview.png");
        }
    }
    
    Ok(())
}

fn read_string(message: &str) -> String {
    println!("{}", message);

    let mut input = String::new();
    std::io::stdin()
        .read_line(&mut input)
        .expect("Can not read user input");
    input
}

// Resizes image to new dimensions using nearest neighbor
fn resize(img: &Image, new_dimensions: (u32, u32)) -> Image {
    let (old_width, old_height) = img.dimensions();
    let (new_width, new_height) = new_dimensions;

    let mut new_image = Image::new(new_width, new_height);

    for (new_x, new_y, pixel) in new_image.enumerate_pixels_mut() {

        // Get the nearest x and y coordinates in the old image to the current x and y coordinates in the new image
        let nearest_x = (new_x as f32 * (old_width  as f32 / new_width  as f32)) as u32;
        let nearest_y = (new_y as f32 * (old_height  as f32 / new_height  as f32)) as u32;

        if let Some(old_pixel) = img.get_pixel_checked(nearest_x, nearest_y) {
            *pixel = *old_pixel;
        }
    }

    new_image
}

// Clamps each channel of an rgb colour to only have certain values defined by combinations
// If combinations is 3 each channel only has 3 discrete (evenly spaced) values
// If in bus mode the resulting rgb value wont have evenly spaced channel values, rather values to be put on a bus
// 
// combinations = 3
// input = (70, 158, 237)
//
// if bus_mode
// output = (1, 2, 3)
// else
// output = (85, 170, 255)
fn clamp_colour(input: Rgb<u8>, combinations: u8, bus_mode: bool) -> Rgb<u8> {
    let mut output = Rgb { 0: [0, 0, 0] };

    let block_size = u8::MAX / combinations;

    for channel in 0..3 {
        let rounded_channel = round(input[channel], block_size);

        if bus_mode {
            output.0[channel] = rounded_channel / block_size;
        } else {
            output.0[channel] = rounded_channel;
        }
    }
    output
}

// Rounds num to nearest specified value
fn round(num: u8, to_nearest: u8) -> u8 {
    let output = ((num as f32 / to_nearest as f32).round() as u8).checked_mul(to_nearest);
    output.unwrap_or_else(|| u8::MAX)
}

// Creates a hex dump of the image
// pixel_bytes represents how many bytes pixel information takes up
fn image_hex_dump(
    img: &Image,
    channel_colour_combinations: u8,
    output_path: &str
) -> Result<(), Error> {

    // Based on the channel colour combinations figure out the width of each channels bus
    // 3 Colour combinations would have a 2 bit bus, becase 3 is the maximum number you can represent with 2 bits
    let bus_bits = (channel_colour_combinations + 1) as f32;
    let bus_bits = bus_bits.ln() / 2.0_f32.ln();
    let bus_bits = bus_bits as u8;

    let pixel_data_bytes = ((bus_bits as f32 * 3.0) / 8.0).ceil() as u8; // Number of bytes required to store 1 pixel

    let mut output = File::create(output_path)?;

    for (_, _, pixel) in img.enumerate_pixels() {

        // Turn pixel data into 4 bytes, with each colour channel taking up the minimum possible space
        let pixel_data = 
            (pixel.0[0] as u32) << (bus_bits * 2) |  // Red, MSB
            (pixel.0[1] as u32) << bus_bits |        // Green
            (pixel.0[2] as u32);                     // Blue, LSB

        let pixel_bytes: [u8; 4] = pixel_data.to_be_bytes();

        // Write bytes to hex file
        let mut bytes_written = 0;
        for i in (0..4).rev() {
            if bytes_written < pixel_data_bytes {
                write!(output, "{:02x?} ", pixel_bytes[i])?;
                bytes_written += 1;
            }
        }
    }

    Ok(())
}



