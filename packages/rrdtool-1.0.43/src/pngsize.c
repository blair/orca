/*****************************************************************************
 * RRDtool 1.0.43  Copyright Tobias Oetiker, 1997 - 2000
 *****************************************************************************
 * pngsize.c  determine the size of a PNG image
 *****************************************************************************/

#include <png.h>

int
PngSize(FILE *fd, long *width, long *height)
{
  png_structp png_read_ptr = 
    png_create_read_struct(PNG_LIBPNG_VER_STRING, 
			   (png_voidp)NULL,
				/* we would need to point to error handlers
				   here to do it properly */
			   (png_error_ptr)NULL, (png_error_ptr)NULL);
    
  png_infop info_ptr = png_create_info_struct(png_read_ptr);

  (*width)=0;
  (*height)=0;

  if (setjmp(png_read_ptr->jmpbuf)){
    png_destroy_read_struct(&png_read_ptr, &info_ptr, (png_infopp)NULL);
    return 0;
  }

  png_init_io(png_read_ptr,fd);
  png_read_info(png_read_ptr, info_ptr);
  (*width)=png_get_image_width(png_read_ptr, info_ptr);
  (*height)=png_get_image_height(png_read_ptr, info_ptr);
  
  png_destroy_read_struct(&png_read_ptr, &info_ptr, NULL);
  if (*width >0 && *height >0) 
    return 1;
  else
    return 0;
}



