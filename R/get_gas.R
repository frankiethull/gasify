# project: gas buddy pixel miner
# purpose: get gas price data from gas buddy, w/o dataset access
# method: image processing
# notes: process image pixels, vectorize, and back into price based on pixel location

# libraries to add using usethis::use_package
# library(dplyr)
# library(tidyr)
# library(magick)
# library(lubridate)
# library(scales)

#' scapes gasbuddy image pixels and converts to df
#'
#' @param period a month number, refer to period_options
#' @param country USA or Canada
#' @param area this is a country, state, city, check out area_options
#' @returns dataframe of prices by date
#' @examples
#' get_gas(18, "USA", "FortCollins")
#' @export


get_gas <- function(period = 18, country = "USA", area = "Chicago"){
chart_url <- paste0("https://charts.gasbuddy.com/ch.gaschart?Country=", country,
                    "&Crude=f&Period=", period,
                    "&Areas=", area,
                    "%2C%2C&Unit=US%20%24%2FG")

chart_img <- magick::image_read(chart_url)

# GET THE PATH VECTOR - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# processing just the xy-grid itself with pads - - -
chart_img %>%
  magick::image_quantize(colorspace = "gray") %>%
  magick::image_transparent("white", fuzz = 20) %>%
  magick::image_background("white") %>%
  magick::image_crop(magick::geometry_area(587, 210, y_off = 56, x_off = 47)) %>%
  magick::image_data() %>%
  as.integer() -> plot_data

# find the xy vector - - - -
# pivot matrix & wrangle,
tidy_pixels <- plot_data %>%
  as.data.frame() %>%
  dplyr::mutate(
    y = dplyr::row_number()
  ) %>%
  tidyr::pivot_longer(-y, names_to = "x", values_to = "val") %>%
  dplyr::mutate(
    x = gsub("V", "", x) %>% as.numeric()
  )

# the grid box is black (0), background is white (255),
# the line comes through greyish, non-constant value
tidy_pixels %>%
  dplyr::filter(val != 0,
         val != 255,
         x > 4,
         y > 4,
         x < 585,
         y < 205) -> tidy_pixels

path_vector <- tidy_pixels %>%
  dplyr::group_by(x) %>%
  dplyr::summarize(
    y = mean(y) * -1
  )

# mining the y axis - - -
y_axis_vector <- chart_img %>%
  magick::image_quantize(colorspace = "gray") %>%
  magick::image_transparent("white", fuzz = 12) %>%
  magick::image_background("white") %>%
  magick::image_negate() %>%
  magick::image_crop(magick::geometry_area(33, 225, y_off = 48, x_off = 15)) %>%
  magick::image_ocr()

# adjustments - -
y_axis_vector %>%
  strsplit(., split = "\n")  %>%
  unlist %>%
  as.data.frame() -> y_axis_vector

y_axis_vector %>%
  dplyr::rename("y" = ".") %>%
  dplyr::mutate( # need to remove decimal, because it's not always recognized... then add back
    y = gsub("\\.", "", y),
    y = sub('(.{1})\\.?(.*)', '\\1.\\2', y),
    y = as.numeric(y)
  ) -> y_axis_vector

# scalars - - - - - - - - -- - - - - - - -- - - -
y_min <- min(y_axis_vector$y, na.rm = TRUE)
y_max <- max(y_axis_vector$y, na.rm = TRUE)

x_max <- Sys.Date()
x_min <- (x_max - lubridate::dmonths(period)) %>% as.Date()

# rescale path vector with scalars - - - - - - - - - - - - -
path_vector %>%
  dplyr::ungroup() %>%
  dplyr::mutate(
    day = dplyr::row_number(),
    date = x_min + lubridate::days(day),
    price = scales::rescale(y, to = c(y_min, y_max))
  ) -> tidy_gasbuddy_df

    return(tidy_gasbuddy_df)
}
