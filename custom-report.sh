#!/bin/bash

                       ##::[[---  FreeNAS S.M.A.R.T Report Script ---]]::##

#==================================================================================================

               # https://github.com/edgarsuit/FreeNAS-Report/blob/master/report.sh
                           # Original by joeschmuck, Bidelu0hm, and melp

#--------------------------------------------------------------------------------------------------

# Email:
  email="email+SMART@gmail.com"

# Global table colors:
  okColor="#c9ffcc"       # S.M.A.R.T Status column if drives pass
  warnColor="#ffd6d6"     # WARN color
  critColor="#ff0000"     # CRITICAL color
  altColor="#f4f4f4"      # Table background row alternates between white and this color

# Zpool status summary table:
  usedWarn=90             # Pool used percentage for CRITICAL color
  scrubAgeWarn=30         # Maximum age (in days) of last pool scrub before CRITICAL color

# S.M.A.R.T status summary table:
  includeSSD="false"      # true: include SSDs in S.M.A.R.T status summary table || false: disable
  tempWarn=40             # Drive temp (in C) at which WARNING color
  tempCrit=45             # Drive temp (in C) at which CRITICAL color
  sectorsCrit=10          # Number of sectors per drive with errors before CRITICAL color
  testAgeWarn=5           # Maximum age (in days) of last S.M.A.R.T test before CRITICAL color
  powerTimeFormat="ymdh"  # Format for power-on hours string - valid options: "ymdh", "ymd", "ym", or "y" (year month day hour)

# FreeNAS config backup:
  configBackup="true"     # false: skip config backup || true: enable config backup
  saveBackup="true"       # false: delete config backup after mail is sent || true: keep in dir below
  backupLocation="/mnt/nas-system/backups/config"

#==================================================================================================

# Auto-generated Parameters:
  host=$(hostname -s)

  logfile="/tmp/smart_report.tmp"
  subject="Status Report and Configuration Backup for ${host}"
  boundary="gc0p4Jq0M2Yt08jU534c0p"

  if [ "$includeSSD" == "true" ]; then
    drives=$(for drive in $(sysctl -n kern.disks); do
      if [ "$(smartctl -i /dev/"${drive}" | grep "SMART support is: Enabled")" ]; then
        printf "%s " "${drive}"
      fi
    done | awk '{for (i=NF; i!=0 ; i--) print $i }')
  else
    drives=$(for drive in $(sysctl -n kern.disks); do
      if [ "$(smartctl -i /dev/"${drive}" | grep "SMART support is: Enabled")" ] && ! [ "$(smartctl -i /dev/"${drive}" | grep "Solid State Device")" ]; then
        printf "%s " "${drive}"
      fi
    done | awk '{for (i=NF; i!=0 ; i--) print $i }')
  fi

  pools=$(zpool list -H -o name)

#--------------------------------------------------------------------------------------------------
# Email pre-formatting

  # Header:
    (
      echo "From: ${email}"
      echo "To: ${email}"
      echo "Subject: ${subject}"
      echo "MIME-Version: 1.0"
      echo "Content-Type: multipart/mixed; boundary=${boundary}"
    ) > "$logfile"

  # Config backup:
    if [ "$configBackup" == "true" ]; then
      # Set up file names, etc. for later:
        tarfile="/tmp/config_backup.tar.gz"
        filename="$(date "+FreeNAS_Config_%Y-%m-%d")"

      # Test config integrity:
        if ! [ "$(sqlite3 /data/freenas-v1.db "pragma integrity_check;")" == "ok" ]; then
          # Config integrity check failed, set MIME content type to html and print warning:
            (
              echo "--${boundary}"
              echo "Content-Type: text/html"
              echo "<b>Automatic backup of FreeNAS configuration has failed! The configuration file is corrupted!</b>"
              echo "<b>You should correct this problem as soon as possible!</b>"
              echo "<br>"
            ) >> "$logfile"
        else
          # Config integrity check passed; copy config db, generate checksums, make .tar.gz archive:
            cp /data/freenas-v1.db "/tmp/${filename}.db"
            md5 "/tmp/${filename}.db" > /tmp/config_backup.md5
            sha256 "/tmp/${filename}.db" > /tmp/config_backup.sha256
            (
              cd "/tmp/" || exit;
              tar -czf "${tarfile}" "./${filename}.db" ./config_backup.md5 ./config_backup.sha256;
            )
            (
              # Write MIME section header for file attachment (encoded with base64)
                echo "--${boundary}"
                echo "Content-Type: application/tar+gzip"
                echo "Content-Transfer-Encoding: base64"
                echo "Content-Disposition: attachment; filename=${filename}.tar.gz"
                base64 "$tarfile"

              # Write MIME section header for html content to come below
                echo "--${boundary}"
                echo "Content-Type: text/html"
            ) >> "$logfile"

          # If logfile saving is enabled, copy .tar.gz file to specified location before it (and everything else) is removed below:
            if [ "$saveBackup" == "true" ]; then
              cp "${tarfile}" "${backupLocation}/${filename}.tar.gz"
            fi

            rm "/tmp/${filename}.db"
            rm /tmp/config_backup.md5
            rm /tmp/config_backup.sha256
            rm "${tarfile}"
        fi
    else
      # Config backup enabled; set up for html-type content:
        (
          echo "--${boundary}"
          echo "Content-Type: text/html"
        ) >> "$logfile"
    fi

#--------------------------------------------------------------------------------------------------
# Report Summary Section (html tables)

  # zpool status summary table:
    (
      # Write HTML table headers to log file; HTML in an email requires 100% in-line styling (no CSS or <style> section), hence the massive tags:
        echo "<br><br>"
        echo "<table style=\"border: 1px solid black; border-collapse: collapse;\">"
        echo "<tr><th colspan=\"9\" style=\"text-align:center; font-size:20px; height:40px; font-family:courier;\">ZPool Status Report Summary</th></tr>"
        echo "<tr>"
        echo "  <th style=\"text-align:center; width:130px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Pool<br>Name</th>"
        echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Status</th>"
        echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Read<br>Errors</th>"
        echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Write<br>Errors</th>"
        echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Cksum<br>Errors</th>"
        echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Used %</th>"
        echo "  <th style=\"text-align:center; width:100px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Scrub<br>Repaired<br>Bytes</th>"
        echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Scrub<br>Errors</th>"
        echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Last<br>Scrub<br>Age</th>"
        echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Last<br>Scrub<br>Time</th>"
        echo "</tr>"
    ) >> "$logfile"

    poolNum=0

    for pool in $pools; do
      # Zpool health summary:
        status="$(zpool list -H -o health "$pool")"

      # Total all read, write, and checksum errors per pool:
        errors="$(zpool status "$pool" | grep -E "(ONLINE|DEGRADED|FAULTED|UNAVAIL|REMOVED)[ \\t]+[0-9]+")"

        readErrors=0
        for err in $(echo "$errors" | awk '{print $3}'); do
          if echo "$err" | grep -E -q "[^0-9]+"; then
            readErrors=1000
            break
          fi
          readErrors=$((readErrors + err))
        done

        writeErrors=0
        for err in $(echo "$errors" | awk '{print $4}'); do
          if echo "$err" | grep -E -q "[^0-9]+"; then
            writeErrors=1000
            break
          fi
          writeErrors=$((writeErrors + err))
        done

        cksumErrors=0
        for err in $(echo "$errors" | awk '{print $5}'); do
          if echo "$err" | grep -E -q "[^0-9]+"; then
            cksumErrors=1000
            break
          fi
          cksumErrors=$((cksumErrors + err))
        done

      # Not sure why this changes values larger than 1000 to ">1K", but it works:
        if [ "$readErrors" -gt 999 ]; then readErrors=">1K"; fi
        if [ "$writeErrors" -gt 999 ]; then writeErrors=">1K"; fi
        if [ "$cksumErrors" -gt 999 ]; then cksumErrors=">1K"; fi

      # Get used capacity percentage of the zpool:
        used="$(zpool list -H -p -o capacity "$pool")"

      # Gather info from most recent scrub; values set to "N/A" initially and overwritten when (and if) it gathers scrub info
        scrubRepBytes="N/A"
        scrubErrors="N/A"
        scrubAge="N/A"
        scrubTime="N/A"
        statusOutput="$(zpool status "$pool")"

        if [ "$(echo "$statusOutput" | grep "scan" | awk '{print $2}')" = "scrub" ]; then
          scrubRepBytes="$(echo "$statusOutput" | grep "scan" | awk '{print $4}')"
          scrubErrors="$(echo "$statusOutput" | grep "scan" | awk '{print $10}')"

          # Convert time/datestamp format presented by zpool status, compare to current date, calculate scrub age:
            scrubDate="$(echo "$statusOutput" | grep "scan" | awk '{print $17"-"$14"-"$15"_"$16}')"
            scrubTS="$(date -j -f "%Y-%b-%e_%H:%M:%S" "$scrubDate" "+%s")"
            currentTS="$(date "+%s")"
            scrubAge=$((((currentTS - scrubTS) + 43200) / 86400))
            scrubTime="$(echo "$statusOutput" | grep "scan" | awk '{print $8}')"
        fi

      # Check if scrub is in progress:
        if [ "$(echo "$statusOutput"| grep "scan" | awk '{print $4}')" = "progress" ]; then
          scrubAge="In Progress"
        fi

      # Set row's background color; alternates between white and $altColor (light gray):
        if [ $((poolNum % 2)) == 1 ]; then bgColor="#ffffff"; else bgColor="$altColor"; fi
        poolNum=$((poolNum + 1))

      # Set up conditions for warning or critical colors to be used in place of standard background colors
        if [ "$status" != "ONLINE" ]; then statusColor="$warnColor"; else statusColor="$bgColor"; fi
        if [ "$readErrors" != "0" ]; then readErrorsColor="$warnColor"; else readErrorsColor="$bgColor"; fi
        if [ "$writeErrors" != "0" ]; then writeErrorsColor="$warnColor"; else writeErrorsColor="$bgColor"; fi
        if [ "$cksumErrors" != "0" ]; then cksumErrorsColor="$warnColor"; else cksumErrorsColor="$bgColor"; fi
        if [ "$used" -gt "$usedWarn" ]; then usedColor="$warnColor"; else usedColor="$bgColor"; fi
        if [ "$scrubRepBytes" != "N/A" ] && [ "$scrubRepBytes" != "0" ]; then scrubRepBytesColor="$warnColor"; else scrubRepBytesColor="$bgColor"; fi
        if [ "$scrubErrors" != "N/A" ] && [ "$scrubErrors" != "0" ]; then scrubErrorsColor="$warnColor"; else scrubErrorsColor="$bgColor"; fi
        if [ "$(echo "$scrubAge" | awk '{print int($1)}')" -gt "$scrubAgeWarn" ]; then scrubAgeColor="$warnColor"; else scrubAgeColor="$bgColor"; fi

        (
          # Use the information gathered above to write the date to the current table row
            printf "<tr style=\"background-color:%s;\">
              <td style=\"text-align:center; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
              <td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
              <td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
              <td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
              <td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
              <td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s%%</td>
              <td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
              <td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
              <td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
              <td style=\"text-align:center; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>
            </tr>\\n" "$bgColor" "$pool" "$statusColor" "$status" "$readErrorsColor" "$readErrors" "$writeErrorsColor" "$writeErrors" "$cksumErrorsColor" \
            "$cksumErrors" "$usedColor" "$used" "$scrubRepBytesColor" "$scrubRepBytes" "$scrubErrorsColor" "$scrubErrors" "$scrubAgeColor" "$scrubAge" "$scrubTime"
        ) >> "$logfile"
    done

    # End of zpool status table
    echo "</table>" >> "$logfile"

#--------------------------------------------------------------------------------------------------
# S.M.A.R.T status summary table:

  (
    # Write HTML table headers to log file
      echo "<br><br>"
      echo "<table style=\"border: 1px solid black; border-collapse: collapse;\">"
      echo "<tr><th colspan=\"15\" style=\"text-align:center; font-size:20px; height:40px; font-family:courier;\">S.M.A.R.T Status Report Summary</th></tr>"
      echo "<tr>"
      echo "  <th style=\"text-align:center; width:100px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Device</th>"
      echo "  <th style=\"text-align:center; width:130px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Serial<br>Number</th>"
      echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">SMART<br>Status</th>"
      echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Temp</th>"
      echo "  <th style=\"text-align:center; width:120px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Power-On<br>Time</th>"
      echo "  <th style=\"text-align:center; width:100px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Start/Stop<br>Count</th>"
      echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Spin<br>Retry<br>Count</th>"
      echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Realloc'd<br>Sectors</th>"
      echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Realloc<br>Events</th>"
      echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Current<br>Pending<br>Sectors</th>"
      echo "  <th style=\"text-align:center; width:120px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Offline<br>Uncorrectable<br>Sectors</th>"
      echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">UltraDMA<br>CRC<br>Errors</th>"
      echo "  <th style=\"text-align:center; width:80px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Seek<br>Error<br>Health</th>"
      echo "  <th style=\"text-align:center; width:100px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Last Test<br>Age (days)</th>"
      echo "  <th style=\"text-align:center; width:100px; height:60px; border:1px solid black; border-collapse:collapse; font-family:courier;\">Last Test<br>Type</th></tr>"
      echo "</tr>"
  ) >> "$logfile"

  for drive in $drives; do
    (
      # For each drive detected, run "smartctl -A -i" and parse its output (whole section is a single, long statement):
          # Pass awk variables (all the -v's) used in other parts of the script. Other variables are calculated in-line with other smartctl calls.
          # pull values out of the original "smartctl -A -i" statement by searching for the text between the //'s.
          # Compute other values (last test's age, on time in YY-MM-DD-HH) and etermine the row's alternating background color
          # Print the HTML code for the current row of the table with all the gathered data.

        smartctl -A -i /dev/"$drive" | \
        awk -v device="$drive" -v tempWarn="$tempWarn" -v tempCrit="$tempCrit" -v sectorsCrit="$sectorsCrit" -v testAgeWarn="$testAgeWarn" \
        -v okColor="$okColor" -v warnColor="$warnColor" -v critColor="$critColor" -v altColor="$altColor" -v powerTimeFormat="$powerTimeFormat" \
        -v lastTestHours="$(smartctl -l selftest /dev/"$drive" | grep "# 1" | awk '{print $9}')" \
        -v lastTestType="$(smartctl -l selftest /dev/"$drive" | grep "# 1" | awk '{print $3}')" \
        -v smartStatus="$(smartctl -H /dev/"$drive" | grep "SMART overall-health" | awk '{print $6}')" ' \
        /Serial Number:/{serial=$3} \
        /Temperature_Celsius/{temp=($10 + 0)} \
        /Power_On_Hours/{onHours=$10} \
        /Start_Stop_Count/{startStop=$10} \
        /Spin_Retry_Count/{spinRetry=$10} \
        /Reallocated_Sector/{reAlloc=$10} \
        /Reallocated_Event_Count/{reAllocEvent=$10} \
        /Current_Pending_Sector/{pending=$10} \
        /Offline_Uncorrectable/{offlineUnc=$10} \
        /UDMA_CRC_Error_Count/{crcErrors=$10} \
        /Seek_Error_Rate/{seekErrorHealth=$4} \
        END {
          testAge=int((onHours - lastTestHours) / 24);
          yrs=int(onHours / 8760);
          mos=int((onHours % 8760) / 730);
          dys=int(((onHours % 8760) % 730) / 24);
          hrs=((onHours % 8760) % 730) % 24;
          if (powerTimeFormat == "ymdh") onTime=yrs "y " mos "m " dys "d " hrs "h";
          else if (powerTimeFormat == "ymd") onTime=yrs "y " mos "m " dys "d";
          else if (powerTimeFormat == "ym") onTime=yrs "y " mos "m";
          else if (powerTimeFormat == "y") onTime=yrs "y";
          else onTime=yrs "y " mos "m " dys "d " hrs "h ";
          if ((substr(device,3) + 0) % 2 == 1) bgColor = "#ffffff"; else bgColor = altColor;
          if (smartStatus != "PASSED") smartStatusColor = critColor; else smartStatusColor = okColor;
          if (temp >= tempCrit) tempColor = critColor; else if (temp >= tempWarn) tempColor = warnColor; else tempColor = bgColor;
          if (spinRetry != "0") spinRetryColor = warnColor; else spinRetryColor = bgColor;
          if ((reAlloc + 0) > sectorsCrit) reAllocColor = critColor; else if (reAlloc != 0) reAllocColor = warnColor; else reAllocColor = bgColor;
          if (reAllocEvent != "0") reAllocEventColor = warnColor; else reAllocEventColor = bgColor;
          if ((pending + 0) > sectorsCrit) pendingColor = critColor; else if (pending != 0) pendingColor = warnColor; else pendingColor = bgColor;
          if ((offlineUnc + 0) > sectorsCrit) offlineUncColor = critColor; else if (offlineUnc != 0) offlineUncColor = warnColor; else offlineUncColor = bgColor;
          if (crcErrors != "0") crcErrorsColor = warnColor; else crcErrorsColor = bgColor;
          if ((seekErrorHealth + 0) < 100) seekErrorHealthColor = warnColor; else seekErrorHealthColor = bgColor;
          if (testAge > testAgeWarn) testAgeColor = warnColor; else testAgeColor = bgColor;
          printf "<tr style=\"background-color:%s;\">\n" \
            "<td style=\"text-align:center; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">/dev/%s</td>\n" \
            "<td style=\"text-align:center; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>\n" \
            "<td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>\n" \
            "<td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%d*C</td>\n" \
            "<td style=\"text-align:center; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>\n" \
            "<td style=\"text-align:center; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>\n" \
            "<td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>\n" \
            "<td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>\n" \
            "<td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>\n" \
            "<td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>\n" \
            "<td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>\n" \
            "<td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>\n" \
            "<td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s%%</td>\n" \
            "<td style=\"text-align:center; background-color:%s; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%d</td>\n" \
            "<td style=\"text-align:center; height:25px; border:1px solid black; border-collapse:collapse; font-family:courier;\">%s</td>\n" \
          "</tr>\n", bgColor, device, serial, smartStatusColor, smartStatus, tempColor, temp, onTime, startStop, spinRetryColor, spinRetry, reAllocColor, reAlloc, \
          reAllocEventColor, reAllocEvent, pendingColor, pending, offlineUncColor, offlineUnc, crcErrorsColor, crcErrors, seekErrorHealthColor, seekErrorHealth, \
          testAgeColor, testAge, lastTestType;
        }'
    ) >> "$logfile"
  done

  # End S.M.A.R.T summary table and summary section:
    (
      echo "</table>"
      echo "<br><br>"
    ) >> "$logfile"

#--------------------------------------------------------------------------------------------------
# Detailed Report Section (monospace text):

  echo "<pre style=\"font-size:14px\">" >> "$logfile"

  # zpool status for each pool:
    for pool in $pools; do
      (
        # Create a simple header and drop the output of zpool status -v
          echo "<b>########## ZPool status report for ${pool} ##########</b>"
          echo "<br>"
            zpool status -v "$pool"
          echo "<br><br>"
      ) >> "$logfile"
    done

  # S.M.A.R.T status for each drive:
    for drive in $drives; do
      # Gather brand and serial number of each drive:
        brand="$(smartctl -i /dev/"$drive" | grep "Model Family" | awk '{print $3, $4, $5}')"
        serial="$(smartctl -i /dev/"$drive" | grep "Serial Number" | awk '{print $3}')"
        (
          # Create a simple header and drop the output of some basic smartctl commands:
            echo "<br>"
            echo "<b>########## S.M.A.R.T status report for ${drive} drive (${brand}: ${serial}) ##########</b>"
              smartctl -H -A -l error /dev/"$drive"
              smartctl -l selftest /dev/"$drive" | grep "Extended \\|Num" | cut -c6- | head -2
              smartctl -l selftest /dev/"$drive" | grep "Short \\|Num" | cut -c6- | head -2 | tail -n -1
            echo "<br><br>"
        ) >> "$logfile"
    done

    # Remove un-needed junk from output:
      sed -i '' -e '/smartctl 6.3/d' "$logfile"
      sed -i '' -e '/Copyright/d' "$logfile"
      sed -i '' -e '/=== START OF READ/d' "$logfile"
      sed -i '' -e '/SMART Attributes Data/d' "$logfile"
      sed -i '' -e '/Vendor Specific SMART/d' "$logfile"
      sed -i '' -e '/SMART Error Log Version/d' "$logfile"

#--------------------------------------------------------------------------------------------------

# End details section, close MIME section:
  (
    echo "</pre>"
    echo "--${boundary}--"
  )  >> "$logfile"

# Email report:
  sendmail -t -oi < "$logfile"
  rm "$logfile"
